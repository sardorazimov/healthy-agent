#ifndef CLEANUP_H
#define CLEANUP_H

#import <Cocoa/Cocoa.h>

#pragma mark - Entry

@interface MiransasCleanupEntry : NSObject
@property(nonatomic, copy)   NSString *path;
@property(nonatomic, copy)   NSString *name;
@property(nonatomic, copy)   NSString *detail;
@property(nonatomic, assign) uint64_t  bytes;
@property(nonatomic, assign) BOOL      selected;
@end

#pragma mark - Helpers

@interface MiransasCleanup : NSObject

+ (uint64_t)recursiveSizeAtPath:(NSString *)path;
+ (NSString *)formatBytes:(uint64_t)bytes;
+ (NSString *)formatRelativeDate:(NSDate *)date;

// Async scan of top-level entries in ~/Library/Caches with recursive sizes,
// sorted by size desc. Result is cached for 5 minutes. completion runs on main.
+ (void)loadCacheEntriesWithCompletion:(void (^)(NSArray<MiransasCleanupEntry *> *entries))completion;
+ (NSArray<MiransasCleanupEntry *> *)cachedCacheEntries;
+ (void)invalidateCacheEntriesCache;

// Same pattern for ~/Downloads.
+ (void)loadDownloadsEntriesWithCompletion:(void (^)(NSArray<MiransasCleanupEntry *> *entries))completion;
+ (NSArray<MiransasCleanupEntry *> *)cachedDownloadsEntries;
+ (void)invalidateDownloadsEntriesCache;

// Recursive scan of files >100 MB anywhere under ~/. Skips ~/Library
// (except ~/Library/Caches), ~/.Trash, and the contents of any package
// (including .app bundles). 5-minute cache. completion runs on main.
+ (void)loadLargeFilesEntriesWithCompletion:(void (^)(NSArray<MiransasCleanupEntry *> *entries))completion;
+ (NSArray<MiransasCleanupEntry *> *)cachedLargeFilesEntries;
+ (void)invalidateLargeFilesEntriesCache;

// Recursive scan for stale project artifact directories under ~/ — looks for
// node_modules, target, .build, dist, build, .next, vendor whose mtime is
// >= 30 days old. Skips ~/Library, ~/.Trash, /Applications, and package
// contents. 5-minute cache. progress and completion run on main.
+ (void)loadStaleArtifactsEntriesWithProgress:(void (^)(NSUInteger checked, NSUInteger total))progress
                                   completion:(void (^)(NSArray<MiransasCleanupEntry *> *entries))completion;
+ (NSArray<MiransasCleanupEntry *> *)cachedStaleArtifactsEntries;
+ (void)invalidateStaleArtifactsEntriesCache;

// Wraps NSWorkspace recycleURLs. completion runs on main queue.
+ (void)moveURLsToTrash:(NSArray<NSURL *> *)urls
             completion:(void (^)(NSUInteger trashedCount, uint64_t reclaimedBytes, NSError *error))completion;

@end

#pragma mark - Card view

@interface MiransasCleanupCard : NSView
@property(nonatomic, copy) void (^onAction)(void);
- (instancetype)initWithTitle:(NSString *)title
                       symbol:(NSString *)symbolName
                  description:(NSString *)description
                  actionTitle:(NSString *)actionTitle;
- (void)setStatsText:(NSString *)text;
- (void)setActionEnabled:(BOOL)enabled;
- (void)setActionHidden:(BOOL)hidden;
- (void)setActionTitle:(NSString *)title;
- (void)setScanning:(BOOL)scanning;
@end

#pragma mark - Review sheet

@interface MiransasCleanupSheet : NSObject
- (instancetype)initWithTitle:(NSString *)title
                     subtitle:(NSString *)subtitle
                      entries:(NSArray<MiransasCleanupEntry *> *)entries
                 extraWarning:(NSString *)extraWarning;
- (void)beginSheetForWindow:(NSWindow *)parent
                 completion:(void (^)(BOOL didTrash, NSUInteger trashedCount, uint64_t reclaimedBytes))completion;
@end

#endif
