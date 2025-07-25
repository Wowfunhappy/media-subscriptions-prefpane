#import "MediaSubscriptionsPane.h"

#define PREF_DOMAIN @"com.mediasubscriptions"
#define PREF_URLS_KEY @"URLs"
#define LAUNCHAGENT_LABEL @"com.mediasubscriptions.downloader"

@implementation MediaSubscriptionsPane

- (NSView *)loadMainView {
    NSView *mainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 668, 280)];
    [self setMainView:mainView];
    
    urls = [[NSMutableArray alloc] init];
    [self loadPreferences];
    
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 40, 628, 220)];
    [scrollView setBorderType:NSBezelBorder];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setAutohidesScrollers:YES];
    
    urlTableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 626, 218)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"URL"];
    [[column headerCell] setStringValue:@"Subscription URLs"];
    [column setWidth:624];
    [urlTableView addTableColumn:column];
    [urlTableView setUsesAlternatingRowBackgroundColors:YES];
    [urlTableView setDelegate:self];
    [urlTableView setDataSource:self];
    
    [scrollView setDocumentView:urlTableView];
    [mainView addSubview:scrollView];
    
    // Button container view at bottom left of scroll view
    NSView *buttonContainer = [[NSView alloc] initWithFrame:NSMakeRect(20, 15, 50, 23)];
    [mainView addSubview:buttonContainer];
    
    // Add button with gradient style
    addButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 25, 23)];
    [addButton setBezelStyle:NSSmallSquareBezelStyle];
    [addButton setButtonType:NSMomentaryPushInButton];
    [addButton setImage:[NSImage imageNamed:NSImageNameAddTemplate]];
    [addButton setImagePosition:NSImageOnly];
    [addButton setBordered:YES];
    [addButton setTarget:self];
    [addButton setAction:@selector(addURL:)];
    [buttonContainer addSubview:addButton];
    
    // Minus button
    removeButton = [[NSButton alloc] initWithFrame:NSMakeRect(24, 0, 25, 23)];
    [removeButton setBezelStyle:NSSmallSquareBezelStyle];
    [removeButton setButtonType:NSMomentaryPushInButton];
    [removeButton setImage:[NSImage imageNamed:NSImageNameRemoveTemplate]];
    [removeButton setImagePosition:NSImageOnly];
    [removeButton setBordered:YES];
    [removeButton setTarget:self];
    [removeButton setAction:@selector(removeURL:)];
    [removeButton setEnabled:NO];
    [buttonContainer addSubview:removeButton];
    
    [urlTableView reloadData];
    
    return mainView;
}

- (void)willSelect {
    [self loadPreferences];
    [urlTableView reloadData];
}

- (void)addURL:(id)sender {
    NSTextField *alertTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    [alertTextField setStringValue:@""];
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Add Subscription URL"];
    [alert setInformativeText:@"Enter the URL of a Youtube channel, a Youtube playlist, or an RSS feed:"];
    [alert addButtonWithTitle:@"Add"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert setAccessoryView:alertTextField];
    
    NSInteger result = [alert runModal];
    
    if (result == NSAlertFirstButtonReturn) {
        NSString *urlString = [alertTextField stringValue];
        if ([urlString length] > 0) {
            [urls addObject:urlString];
            [self savePreferences];
            [urlTableView reloadData];
            [self updateInfrastructure];
        }
    }
}

- (void)removeURL:(id)sender {
    NSInteger selectedRow = [urlTableView selectedRow];
    if (selectedRow >= 0) {
        [urls removeObjectAtIndex:selectedRow];
        [self savePreferences];
        [urlTableView reloadData];
        [self updateInfrastructure];
    }
}

- (void)savePreferences {
    CFPreferencesSetValue((CFStringRef)PREF_URLS_KEY,
                          (__bridge CFPropertyListRef)urls,
                          (CFStringRef)PREF_DOMAIN,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSynchronize((CFStringRef)PREF_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

- (void)loadPreferences {
    CFArrayRef savedURLs = (CFArrayRef)CFPreferencesCopyValue((CFStringRef)PREF_URLS_KEY,
                                                               (CFStringRef)PREF_DOMAIN,
                                                               kCFPreferencesCurrentUser,
                                                               kCFPreferencesAnyHost);
    if (savedURLs) {
        [urls setArray:(__bridge NSArray *)savedURLs];
        CFRelease(savedURLs);
    }
}

- (void)updateInfrastructure {
    if ([urls count] == 0) {
        [self teardownInfrastructure];
    } else {
        [self setupInfrastructure];
    }
}

- (void)setupInfrastructure {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    
    // Create LaunchAgents directory if it doesn't exist
    NSString *launchAgentsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents"];
    [fm createDirectoryAtPath:launchAgentsDir withIntermediateDirectories:YES attributes:nil error:&error];
    
    [fm createDirectoryAtPath:[self applicationSupportPath] withIntermediateDirectories:YES attributes:nil error:&error];
    [fm createDirectoryAtPath:[[self applicationSupportPath] stringByAppendingPathComponent:@"archives"] withIntermediateDirectories:YES attributes:nil error:&error];
    [fm createDirectoryAtPath:[self logsPath] withIntermediateDirectories:YES attributes:nil error:&error];
    [fm createDirectoryAtPath:[self cachesPath] withIntermediateDirectories:YES attributes:nil error:&error];
    
    NSString *bundlePath = [[self bundle] bundlePath];
    NSString *resourcesPath = [bundlePath stringByAppendingPathComponent:@"Contents/Resources"];
    NSString *downloaderPath = [resourcesPath stringByAppendingPathComponent:@"downloader.sh"];
    
    NSDictionary *launchAgentDict = @{
        @"Label": LAUNCHAGENT_LABEL,
        @"ProgramArguments": @[@"/bin/sh", downloaderPath, resourcesPath],
        @"StartInterval": @3600,
        @"StandardOutPath": [[self logsPath] stringByAppendingPathComponent:@"downloader.log"],
        @"StandardErrorPath": [[self logsPath] stringByAppendingPathComponent:@"downloader.error.log"]
    };
    
    NSString *launchAgentPath = [self launchAgentPath];
    [launchAgentDict writeToFile:launchAgentPath atomically:YES];
    
    NSTask *loadTask = [[NSTask alloc] init];
    [loadTask setLaunchPath:@"/bin/launchctl"];
    [loadTask setArguments:@[@"load", @"-w", launchAgentPath]];
    [loadTask launch];
    [loadTask waitUntilExit];
}

- (void)teardownInfrastructure {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSTask *unloadTask = [[NSTask alloc] init];
    [unloadTask setLaunchPath:@"/bin/launchctl"];
    [unloadTask setArguments:@[@"unload", @"-w", [self launchAgentPath]]];
    [unloadTask launch];
    [unloadTask waitUntilExit];
    
    [fm removeItemAtPath:[self launchAgentPath] error:nil];
    [fm removeItemAtPath:[self applicationSupportPath] error:nil];
    [fm removeItemAtPath:[self logsPath] error:nil];
    [fm removeItemAtPath:[self cachesPath] error:nil];
    
    // Clear the URLs preference
    CFPreferencesSetValue((CFStringRef)PREF_URLS_KEY, NULL, (CFStringRef)PREF_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize((CFStringRef)PREF_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

- (NSString *)launchAgentPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/com.mediasubscriptions.downloader.plist"];
}

- (NSString *)applicationSupportPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MediaSubscriptions"];
}

- (NSString *)logsPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MediaSubscriptions"];
}

- (NSString *)cachesPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/MediaSubscriptions"];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [urls count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    return [urls objectAtIndex:row];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    [urls replaceObjectAtIndex:row withObject:object];
    [self savePreferences];
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [removeButton setEnabled:([urlTableView selectedRow] >= 0)];
}

@end