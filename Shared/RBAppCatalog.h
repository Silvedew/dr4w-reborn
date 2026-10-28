#import <Foundation/Foundation.h>

// Returns nil when LaunchServices cannot be queried; an empty array is a valid result.
NSArray<NSDictionary *> *RBInstalledApplications(void);
NSArray<NSDictionary *> *RBFilterApplications(NSArray<NSDictionary *> *applications, NSString *query);
