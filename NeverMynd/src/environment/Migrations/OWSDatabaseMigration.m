//  Created by Michael Kirk on 9/28/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSDatabaseMigration.h"
#import <SignalServiceKit/TSStorageManager.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDatabaseMigration

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
{
    self = [super initWithUniqueId:[self.class migrationId]];
    if (!self) {
        return self;
    }

    _storageManager = storageManager;

    return self;
}

+ (MTLPropertyStorage)storageBehaviorForPropertyWithKey:(NSString *)propertyKey
{
    if ([propertyKey isEqualToString:@"storageManager"]) {
        return MTLPropertyStorageNone;
    } else {
        return [super storageBehaviorForPropertyWithKey:propertyKey];
    }
}

+ (NSString *)migrationId
{
    @throw [NSException
        exceptionWithName:NSInternalInconsistencyException
                   reason:[NSString stringWithFormat:@"Must override %@ in subclass", NSStringFromSelector(_cmd)]
                 userInfo:nil];
}

+ (NSString *)collection
{
    // We want all subclasses in the same collection
    return @"OWSDatabaseMigration";
}

- (void)runUpWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    @throw [NSException
        exceptionWithName:NSInternalInconsistencyException
                   reason:[NSString stringWithFormat:@"Must override %@ in subclass", NSStringFromSelector(_cmd)]
                 userInfo:nil];
}

- (void)runUp
{
    [self.storageManager.newDatabaseConnection
        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            [self runUpWithTransaction:transaction];
        }
        completionBlock:^{
            DDLogInfo(@"Completed migration %@", self.uniqueId);
            [self save];
        }];
}

/**
 * Try to avoid using this.
 */
- (void)runUpWithBlockingMigration
{
    [self.storageManager.newDatabaseConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            [self runUpWithTransaction:transaction];
        }];
    DDLogInfo(@"Completed migration %@", self.uniqueId);
    [self save];
}

@end

NS_ASSUME_NONNULL_END
