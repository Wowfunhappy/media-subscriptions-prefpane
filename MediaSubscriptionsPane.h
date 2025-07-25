#import <PreferencePanes/PreferencePanes.h>

@interface MediaSubscriptionsPane : NSPreferencePane <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSDatePickerCellDelegate> {
    NSTableView *urlTableView;
    NSMutableArray *subscriptions;
    NSButton *addButton;
    NSButton *removeButton;
    NSMutableDictionary *titleCache;
    NSDatePicker *timePicker;
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
- (void)fetchTitleForURL:(NSString *)urlString completion:(void (^)(NSString *title))completion;

@end