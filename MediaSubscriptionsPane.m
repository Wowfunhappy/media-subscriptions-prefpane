#import "MediaSubscriptionsPane.h"

#define PREF_DOMAIN @"com.mediasubscriptions"
#define PREF_URLS_KEY @"URLs"
#define LAUNCHAGENT_LABEL @"com.mediasubscriptions.downloader"

@implementation MediaSubscriptionsPane

- (NSView *)loadMainView {
    NSView *mainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 668, 280)];
    [self setMainView:mainView];
    
    subscriptions = [[NSMutableArray alloc] init];
    titleCache = [[NSMutableDictionary alloc] init];
    [self loadPreferences];
    
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 40, 628, 220)];
    [scrollView setBorderType:NSBezelBorder];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setAutohidesScrollers:YES];
    
    urlTableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 626, 218)];
    
    NSTableColumn *titleColumn = [[NSTableColumn alloc] initWithIdentifier:@"Title"];
    [[titleColumn headerCell] setStringValue:@"Title"];
    [titleColumn setWidth:200];
    [urlTableView addTableColumn:titleColumn];
    
    NSTableColumn *urlColumn = [[NSTableColumn alloc] initWithIdentifier:@"URL"];
    [[urlColumn headerCell] setStringValue:@"URL"];
    [urlColumn setWidth:424];
    [urlTableView addTableColumn:urlColumn];
    
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
    NSMutableDictionary *subscription = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                         @"", @"url",
                                         @"", @"title",
                                         nil];
    [subscriptions addObject:subscription];
    [self savePreferences];
    [urlTableView reloadData];
    [self updateInfrastructure];
    
    NSInteger newRow = [subscriptions count] - 1;
    [urlTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:newRow] byExtendingSelection:NO];
    [urlTableView scrollRowToVisible:newRow];
    
    NSInteger urlColumnIndex = [urlTableView columnWithIdentifier:@"URL"];
    [urlTableView editColumn:urlColumnIndex row:newRow withEvent:nil select:YES];
}

- (void)removeURL:(id)sender {
    NSInteger selectedRow = [urlTableView selectedRow];
    if (selectedRow >= 0) {
        [subscriptions removeObjectAtIndex:selectedRow];
        [self savePreferences];
        [urlTableView reloadData];
        [self updateInfrastructure];
    }
}

- (void)savePreferences {
    CFPreferencesSetValue((CFStringRef)PREF_URLS_KEY,
                          (__bridge CFPropertyListRef)subscriptions,
                          (CFStringRef)PREF_DOMAIN,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesSynchronize((CFStringRef)PREF_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

- (void)loadPreferences {
    CFArrayRef savedData = (CFArrayRef)CFPreferencesCopyValue((CFStringRef)PREF_URLS_KEY,
                                                               (CFStringRef)PREF_DOMAIN,
                                                               kCFPreferencesCurrentUser,
                                                               kCFPreferencesAnyHost);
    if (savedData) {
        NSArray *data = (__bridge NSArray *)savedData;
        [subscriptions removeAllObjects];
        
        for (id item in data) {
            if ([item isKindOfClass:[NSString class]]) {
                NSMutableDictionary *subscription = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                                     item, @"url",
                                                     @"...", @"title",
                                                     nil];
                [subscriptions addObject:subscription];
                
                [self fetchTitleForURL:item completion:^(NSString *title) {
                    if ([title isEqualToString:@"__HTTP_ERROR__"]) {
                        // Remove this subscription as it returns 404
                        NSInteger rowIndex = [subscriptions indexOfObject:subscription];
                        if (rowIndex != NSNotFound) {
                            [subscriptions removeObjectAtIndex:rowIndex];
                            [self savePreferences];
                            [urlTableView reloadData];
                            [self updateInfrastructure];
                        }
                    } else {
                        [subscription setObject:title forKey:@"title"];
                        [self savePreferences];
                        [urlTableView reloadData];
                    }
                }];
            } else if ([item isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *subscription = [NSMutableDictionary dictionaryWithDictionary:item];
                [subscriptions addObject:subscription];
                
                NSString *url = [subscription objectForKey:@"url"];
                NSString *title = [subscription objectForKey:@"title"];
                if (url && title) {
                    // Don't cache placeholder titles, re-fetch them
                    if ([title isEqualToString:@"..."]) {
                        [self fetchTitleForURL:url completion:^(NSString *fetchedTitle) {
                            if ([fetchedTitle isEqualToString:@"__HTTP_ERROR__"]) {
                                // Remove this subscription as it returns an error
                                NSInteger rowIndex = [subscriptions indexOfObject:subscription];
                                if (rowIndex != NSNotFound) {
                                    [subscriptions removeObjectAtIndex:rowIndex];
                                    [self savePreferences];
                                    [urlTableView reloadData];
                                    [self updateInfrastructure];
                                }
                            } else {
                                [subscription setObject:fetchedTitle forKey:@"title"];
                                [self savePreferences];
                                [urlTableView reloadData];
                            }
                        }];
                    } else {
                        [titleCache setObject:title forKey:url];
                    }
                }
            }
        }
        
        CFRelease(savedData);
    }
}

- (void)updateInfrastructure {
    if ([subscriptions count] == 0) {
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
    
    NSString *launchAgentPath = [self launchAgentPath];
    if ([fm fileExistsAtPath:launchAgentPath]) {
        NSTask *unloadTask = [[NSTask alloc] init];
        [unloadTask setLaunchPath:@"/bin/launchctl"];
        [unloadTask setArguments:@[@"unload", @"-w", launchAgentPath]];
        [unloadTask launch];
        [unloadTask waitUntilExit];
    }
    
    [fm removeItemAtPath:launchAgentPath error:nil];
    [fm removeItemAtPath:[self applicationSupportPath] error:nil];
    [fm removeItemAtPath:[self logsPath] error:nil];
    [fm removeItemAtPath:[self cachesPath] error:nil];
    
    // Clear the URLs preference - set to empty array instead of NULL to avoid crash
    NSArray *emptyArray = @[];
    CFPreferencesSetValue((CFStringRef)PREF_URLS_KEY, (__bridge CFArrayRef)emptyArray, (CFStringRef)PREF_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
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
    return [subscriptions count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row >= [subscriptions count]) {
        return @"";
    }
    
    NSDictionary *subscription = [subscriptions objectAtIndex:row];
    NSString *identifier = [tableColumn identifier];
    
    if ([identifier isEqualToString:@"Title"]) {
        return [subscription objectForKey:@"title"];
    } else if ([identifier isEqualToString:@"URL"]) {
        return [subscription objectForKey:@"url"];
    }
    
    return nil;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row >= [subscriptions count]) {
        return;
    }
    
    NSMutableDictionary *subscription = [subscriptions objectAtIndex:row];
    NSString *identifier = [tableColumn identifier];
    
    if ([identifier isEqualToString:@"URL"]) {
        NSString *oldURL = [subscription objectForKey:@"url"];
        NSString *newURL = (NSString *)object;
        
        // Check if URL is valid and not a duplicate
        BOOL isValid = [self isValidURL:newURL];
        BOOL isDuplicate = [self isDuplicateURL:newURL excludingIndex:row];
        
        if (!isValid || isDuplicate) {
            // If the old URL was valid, restore it
            if ([self isValidURL:oldURL] && ![self isDuplicateURL:oldURL excludingIndex:row]) {
                // Keep the old URL, just refresh the table
                [urlTableView reloadData];
                return;
            } else {
                // Otherwise, remove the row (same as empty URL)
                [subscriptions removeObjectAtIndex:row];
                [self savePreferences];
                [urlTableView reloadData];
                [self updateInfrastructure];
                return;
            }
        }
        
        [subscription setObject:newURL forKey:@"url"];
        
        if (![newURL isEqualToString:oldURL]) {
            [subscription setObject:@"..." forKey:@"title"];
            [self savePreferences];
            [urlTableView reloadData];
            
            [self fetchTitleForURL:newURL completion:^(NSString *title) {
                if ([title isEqualToString:@"__HTTP_ERROR__"]) {
                    // Find the row index for this subscription
                    NSInteger rowIndex = [subscriptions indexOfObject:subscription];
                    if (rowIndex != NSNotFound) {
                        [subscriptions removeObjectAtIndex:rowIndex];
                        [self savePreferences];
                        [urlTableView reloadData];
                        [self updateInfrastructure];
                    }
                } else {
                    // Keep "..." or set the actual title
                    [subscription setObject:title forKey:@"title"];
                    [self savePreferences];
                    [urlTableView reloadData];
                }
            }];
        }
    }
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [removeButton setEnabled:([urlTableView selectedRow] >= 0)];
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([[tableColumn identifier] isEqualToString:@"Title"]) {
        // If user tries to edit title, redirect to URL column
        NSInteger urlColumnIndex = [tableView columnWithIdentifier:@"URL"];
        [tableView editColumn:urlColumnIndex row:row withEvent:nil select:YES];
        return NO;
    }
    // Only allow editing the URL column
    return [[tableColumn identifier] isEqualToString:@"URL"];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if ([notification object] == urlTableView) {
        // Get the text from the notification's userInfo
        NSTextView *textView = [[notification userInfo] objectForKey:@"NSFieldEditor"];
        NSString *text = [textView string];
        
        NSInteger editedRow = [urlTableView editedRow];
        NSInteger editedColumn = [urlTableView editedColumn];
        
        // Check if we were editing the URL column
        if (editedRow >= 0 && editedRow < [subscriptions count] && editedColumn >= 0) {
            NSTableColumn *column = [[urlTableView tableColumns] objectAtIndex:editedColumn];
            if ([[column identifier] isEqualToString:@"URL"]) {
                // Check if URL is empty, invalid, or duplicate
                BOOL isEmpty = [text length] == 0;
                BOOL isInvalid = ![self isValidURL:text];
                BOOL isDuplicate = [self isDuplicateURL:text excludingIndex:editedRow];
                
                if (isEmpty || isInvalid || isDuplicate) {
                    // Use performSelector to delay the removal until after the current event loop
                    [self performSelector:@selector(removeInvalidRowAtIndex:) 
                               withObject:[NSNumber numberWithInteger:editedRow] 
                               afterDelay:0.0];
                }
            }
        }
    }
}

- (void)removeInvalidRowAtIndex:(NSNumber *)indexNumber {
    NSInteger row = [indexNumber integerValue];
    if (row >= 0 && row < [subscriptions count]) {
        NSDictionary *subscription = [subscriptions objectAtIndex:row];
        NSString *url = [subscription objectForKey:@"url"];
        
        // Remove if URL is empty, invalid, or duplicate
        BOOL isEmpty = [url length] == 0;
        BOOL isInvalid = ![self isValidURL:url];
        BOOL isDuplicate = [self isDuplicateURL:url excludingIndex:row];
        
        if (isEmpty || isInvalid || isDuplicate) {
            [subscriptions removeObjectAtIndex:row];
            [self savePreferences];
            [urlTableView reloadData];
            [self updateInfrastructure];
        }
    }
}

- (BOOL)isValidURL:(NSString *)urlString {
    if ([urlString length] == 0) {
        return NO;
    }
    
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url || !url.scheme || !url.host) {
        return NO;
    }
    
    // Check for supported schemes
    NSString *scheme = [url.scheme lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return NO;
    }
    
    return YES;
}

- (BOOL)isDuplicateURL:(NSString *)urlString excludingIndex:(NSInteger)excludeIndex {
    for (NSInteger i = 0; i < [subscriptions count]; i++) {
        if (i == excludeIndex) {
            continue;
        }
        NSDictionary *subscription = [subscriptions objectAtIndex:i];
        NSString *existingURL = [subscription objectForKey:@"url"];
        if ([urlString isEqualToString:existingURL]) {
            return YES;
        }
    }
    return NO;
}

- (void)fetchTitleForURL:(NSString *)urlString completion:(void (^)(NSString *title))completion {
    NSString *cachedTitle = [titleCache objectForKey:urlString];
    // Don't use cached title if it's the placeholder
    if (cachedTitle && ![cachedTitle isEqualToString:@"..."]) {
        completion(cachedTitle);
        return;
    }
    
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        completion(@"__HTTP_ERROR__");
        return;
    }
    
    // Create a custom configuration with shorter timeout
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 10.0; // 10 second timeout
    config.timeoutIntervalForResource = 10.0;
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // Check for HTTP response
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if ([httpResponse isKindOfClass:[NSHTTPURLResponse class]]) {
            if (httpResponse.statusCode >= 400) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Use a special marker for HTTP errors
                    completion(@"__HTTP_ERROR__");
                });
                return;
            }
        }
        
        if (error || !data) {
            // Check if this is a network connectivity issue
            if (error && ([error.domain isEqualToString:NSURLErrorDomain] && 
                         (error.code == NSURLErrorNotConnectedToInternet ||
                          error.code == NSURLErrorNetworkConnectionLost ||
                          error.code == NSURLErrorDNSLookupFailed ||
                          error.code == NSURLErrorCannotFindHost ||
                          error.code == NSURLErrorCannotConnectToHost ||
                          error.code == NSURLErrorTimedOut))) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Keep the "..." for network connectivity issues
                    completion(@"...");
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Other errors are treated as invalid URL
                    completion(@"__HTTP_ERROR__");
                });
            }
            return;
        }
        
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!html) {
            html = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        }
        
        NSString *title = @"No title found";
        
        NSRange titleStart = [html rangeOfString:@"<title>" options:NSCaseInsensitiveSearch];
        if (titleStart.location != NSNotFound) {
            NSRange searchRange = NSMakeRange(titleStart.location + titleStart.length, [html length] - titleStart.location - titleStart.length);
            NSRange titleEnd = [html rangeOfString:@"</title>" options:NSCaseInsensitiveSearch range:searchRange];
            if (titleEnd.location != NSNotFound) {
                NSRange titleRange = NSMakeRange(titleStart.location + titleStart.length, titleEnd.location - titleStart.location - titleStart.length);
                title = [html substringWithRange:titleRange];
                title = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                
                title = [title stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
                title = [title stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
                title = [title stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
                title = [title stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
                title = [title stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
                
                if ([title hasSuffix:@" - YouTube"]) {
                    title = [title substringToIndex:[title length] - 10];
                }
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->titleCache setObject:title forKey:urlString];
            completion(title);
        });
    }];
    
    [task resume];
}

@end