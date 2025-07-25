#import <PreferencePanes/PreferencePanes.h>

@interface MediaSubscriptionsPane : NSPreferencePane <NSTableViewDataSource, NSTableViewDelegate> {
    NSTableView *urlTableView;
    NSMutableArray *urls;
    NSButton *addButton;
    NSButton *removeButton;
}

- (void)addURL:(id)sender;
- (void)removeURL:(id)sender;
- (void)savePreferences;
- (void)loadPreferences;
- (void)updateInfrastructure;
- (void)setupInfrastructure;
- (void)teardownInfrastructure;
- (NSString *)launchAgentPath;
- (NSString *)applicationSupportPath;
- (NSString *)logsPath;
- (NSString *)cachesPath;

@end