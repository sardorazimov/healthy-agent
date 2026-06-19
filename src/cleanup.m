#import "cleanup.h"
#import "ui_helpers.h"

#import <QuartzCore/QuartzCore.h>

#pragma mark - Entry

@implementation MiransasCleanupEntry
- (void)dealloc {
    [_path release];
    [_name release];
    [_detail release];
    [super dealloc];
}
@end

#pragma mark - Flipped helper view

@interface MiransasFlippedView : NSView
@end
@implementation MiransasFlippedView
- (BOOL)isFlipped { return YES; }
@end

#pragma mark - Bezeled button with pointing-hand cursor

@interface MiransasBezeledButton : NSButton
@end
@implementation MiransasBezeledButton
- (void)resetCursorRects {
    if (!self.isEnabled || self.isHidden) return;
    [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]];
}
@end

// Configures a button to look like the standard rounded macOS bezel button —
// same chrome as the header Quit button.
static void miransas_style_button(NSButton *b) {
    [b setBordered:YES];
    [b setButtonType:NSButtonTypeMomentaryPushIn];
    [b setBezelStyle:NSBezelStyleRounded];
    [b setControlSize:NSControlSizeRegular];
    [b setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular]];
    [b setAlphaValue:1.0];
}

#pragma mark - Helpers (MiransasCleanup)

static NSArray<MiransasCleanupEntry *> *gCachedEntries = nil;
static NSDate *gCachedEntriesTimestamp = nil;
static BOOL gCacheScanInFlight = NO;
static NSMutableArray *gCacheScanWaiters = nil;

static NSArray<MiransasCleanupEntry *> *gCachedDownloads = nil;
static NSDate *gCachedDownloadsTimestamp = nil;
static BOOL gDownloadsScanInFlight = NO;
static NSMutableArray *gDownloadsScanWaiters = nil;

static NSArray<MiransasCleanupEntry *> *gCachedLargeFiles = nil;
static NSDate *gCachedLargeFilesTimestamp = nil;
static BOOL gLargeFilesScanInFlight = NO;
static NSMutableArray *gLargeFilesScanWaiters = nil;

static NSArray<MiransasCleanupEntry *> *gCachedStaleArtifacts = nil;
static NSDate *gCachedStaleArtifactsTimestamp = nil;
static BOOL gStaleArtifactsScanInFlight = NO;
static NSMutableArray *gStaleArtifactsScanWaiters = nil;

static NSArray<MiransasCleanupEntry *> *scan_top_level_entries(NSString *dirPath,
                                                                BOOL filesOnly) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [fm contentsOfDirectoryAtPath:dirPath error:NULL];
    NSMutableArray<MiransasCleanupEntry *> *out = [NSMutableArray array];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;
        NSString *full = [dirPath stringByAppendingPathComponent:name];
        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:NULL];
        if (!attrs) continue;
        if (filesOnly && ![[attrs fileType] isEqualToString:NSFileTypeRegular]) continue;
        if (filesOnly &&
            [[name pathExtension] caseInsensitiveCompare:@"download"] == NSOrderedSame) continue;
        MiransasCleanupEntry *e = [[MiransasCleanupEntry alloc] init];
        e.path = full;
        e.name = name;
        e.bytes = [MiransasCleanup recursiveSizeAtPath:full];
        NSDate *mtime = [attrs objectForKey:NSFileModificationDate];
        e.detail = [NSString stringWithFormat:@"Modified %@",
                    [MiransasCleanup formatRelativeDate:mtime]];
        [out addObject:e];
        [e release];
    }
    [out sortUsingComparator:^NSComparisonResult(MiransasCleanupEntry *a,
                                                  MiransasCleanupEntry *b) {
        if (b.bytes > a.bytes) return NSOrderedDescending;
        if (b.bytes < a.bytes) return NSOrderedAscending;
        return [a.name caseInsensitiveCompare:b.name];
    }];
    return [[out copy] autorelease];
}

static NSString *abbreviate_home_path(NSString *path, NSString *home) {
    if ([path isEqualToString:home]) return @"~";
    NSString *homePrefix = [home stringByAppendingString:@"/"];
    if ([path hasPrefix:homePrefix]) {
        return [@"~/" stringByAppendingString:[path substringFromIndex:homePrefix.length]];
    }
    return path;
}

static NSArray<MiransasCleanupEntry *> *scan_large_files(NSString *homePath,
                                                         uint64_t thresholdBytes) {
    NSURL *homeURL = [NSURL fileURLWithPath:homePath isDirectory:YES];
    NSString *libraryPath = [homePath stringByAppendingPathComponent:@"Library"];
    NSString *libraryPrefix = [libraryPath stringByAppendingString:@"/"];
    NSString *libraryCachesPath = [libraryPath stringByAppendingPathComponent:@"Caches"];
    NSString *libraryCachesPrefix = [libraryCachesPath stringByAppendingString:@"/"];
    NSString *trashPath = [homePath stringByAppendingPathComponent:@".Trash"];
    NSString *applicationsPath = @"/Applications";

    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *en =
        [fm enumeratorAtURL:homeURL
 includingPropertiesForKeys:@[NSURLFileSizeKey,
                              NSURLIsRegularFileKey,
                              NSURLIsDirectoryKey,
                              NSURLContentAccessDateKey,
                              NSURLContentModificationDateKey,
                              NSURLNameKey]
                    options:(NSDirectoryEnumerationSkipsHiddenFiles |
                             NSDirectoryEnumerationSkipsPackageDescendants)
               errorHandler:^BOOL(NSURL *u, NSError *err) {
                   (void)u; (void)err;
                   return YES;
               }];

    NSMutableArray<MiransasCleanupEntry *> *out = [NSMutableArray array];

    for (NSURL *u in en) {
        @autoreleasepool {
            NSString *path = u.path;
            if (!path) continue;

            NSNumber *isDir = nil;
            [u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:NULL];

            if (isDir && isDir.boolValue) {
                BOOL skip = NO;
                if ([path hasPrefix:libraryPrefix]) {
                    if (![path isEqualToString:libraryCachesPath] &&
                        ![path hasPrefix:libraryCachesPrefix]) {
                        skip = YES;
                    }
                }
                if ([path isEqualToString:trashPath]) skip = YES;
                if ([path isEqualToString:applicationsPath] ||
                    [path hasPrefix:[applicationsPath stringByAppendingString:@"/"]]) {
                    skip = YES;
                }
                if ([[path pathExtension] caseInsensitiveCompare:@"app"] == NSOrderedSame) {
                    skip = YES;
                }
                if (skip) [en skipDescendants];
                continue;
            }

            NSNumber *isFile = nil;
            [u getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:NULL];
            if (!isFile || !isFile.boolValue) continue;

            NSNumber *sz = nil;
            if (![u getResourceValue:&sz forKey:NSURLFileSizeKey error:NULL] || !sz) continue;
            uint64_t bytes = sz.unsignedLongLongValue;
            if (bytes < thresholdBytes) continue;

            NSDate *accessed = nil;
            [u getResourceValue:&accessed forKey:NSURLContentAccessDateKey error:NULL];
            if (!accessed) {
                [u getResourceValue:&accessed forKey:NSURLContentModificationDateKey error:NULL];
            }

            NSString *parent = [path stringByDeletingLastPathComponent];
            NSString *displayParent = abbreviate_home_path(parent, homePath);

            MiransasCleanupEntry *e = [[MiransasCleanupEntry alloc] init];
            e.path = path;
            e.name = u.lastPathComponent;
            e.bytes = bytes;
            NSString *accessedStr = accessed
                ? [MiransasCleanup formatRelativeDate:accessed]
                : @"unknown";
            e.detail = [NSString stringWithFormat:@"%@  ·  Accessed %@",
                        displayParent, accessedStr];
            [out addObject:e];
            [e release];
        }
    }

    [out sortUsingComparator:^NSComparisonResult(MiransasCleanupEntry *a,
                                                  MiransasCleanupEntry *b) {
        if (b.bytes > a.bytes) return NSOrderedDescending;
        if (b.bytes < a.bytes) return NSOrderedAscending;
        return [a.name caseInsensitiveCompare:b.name];
    }];
    return [[out copy] autorelease];
}

static NSArray<NSURL *> *collect_stale_artifact_candidates(NSString *homePath) {
    NSURL *homeURL = [NSURL fileURLWithPath:homePath isDirectory:YES];
    NSString *libraryPath = [homePath stringByAppendingPathComponent:@"Library"];
    NSString *libraryPrefix = [libraryPath stringByAppendingString:@"/"];
    NSString *trashPath = [homePath stringByAppendingPathComponent:@".Trash"];
    NSString *applicationsPath = @"/Applications";
    NSString *applicationsPrefix = [applicationsPath stringByAppendingString:@"/"];

    NSSet<NSString *> *artifactNames = [NSSet setWithObjects:
        @"node_modules", @"target", @".build", @"dist",
        @"build", @".next", @"vendor", nil];
    NSSet<NSString *> *allowedHidden = [NSSet setWithObjects:
        @".build", @".next", nil];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *en =
        [fm enumeratorAtURL:homeURL
 includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLNameKey]
                    options:NSDirectoryEnumerationSkipsPackageDescendants
               errorHandler:^BOOL(NSURL *u, NSError *err) {
                   (void)u; (void)err;
                   return YES;
               }];

    NSMutableArray<NSURL *> *candidates = [NSMutableArray array];

    for (NSURL *u in en) {
        @autoreleasepool {
            NSString *path = u.path;
            if (!path) continue;

            NSNumber *isDir = nil;
            [u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:NULL];
            if (!isDir || !isDir.boolValue) continue;

            NSString *baseName = [path lastPathComponent];

            // Hidden dirs: skip everything dot-prefixed except .build / .next
            // (themselves artifacts we want to find).
            if ([baseName hasPrefix:@"."] && ![allowedHidden containsObject:baseName]) {
                [en skipDescendants];
                continue;
            }

            // Excluded subtrees.
            BOOL excluded = NO;
            if ([path isEqualToString:libraryPath] || [path hasPrefix:libraryPrefix]) excluded = YES;
            if ([path isEqualToString:trashPath]) excluded = YES;
            if ([path isEqualToString:applicationsPath] || [path hasPrefix:applicationsPrefix]) excluded = YES;
            if ([[path pathExtension] caseInsensitiveCompare:@"app"] == NSOrderedSame) excluded = YES;
            if (excluded) {
                [en skipDescendants];
                continue;
            }

            if (![artifactNames containsObject:baseName]) continue;

            // Matching artifact name. Don't descend into it — its contents are
            // not separately interesting and may contain nested node_modules etc.
            [candidates addObject:u];
            [en skipDescendants];
        }
    }
    return [[candidates copy] autorelease];
}

static NSArray<MiransasCleanupEntry *> *scan_stale_artifacts(NSString *homePath,
                                                              NSTimeInterval staleThreshold,
                                                              void (^progress)(NSUInteger, NSUInteger)) {
    NSArray<NSURL *> *candidates = collect_stale_artifact_candidates(homePath);
    NSUInteger total = candidates.count;
    if (progress) progress(0, total);

    NSDate *now = [NSDate date];
    NSMutableArray<MiransasCleanupEntry *> *out = [NSMutableArray array];
    NSTimeInterval lastProgressTime = 0.0;

    for (NSUInteger i = 0; i < total; i++) {
        @autoreleasepool {
            NSURL *u = candidates[i];
            NSString *path = u.path;
            if (!path) continue;

            NSDate *mtime = nil;
            [u getResourceValue:&mtime forKey:NSURLContentModificationDateKey error:NULL];
            if (mtime && [now timeIntervalSinceDate:mtime] >= staleThreshold) {
                uint64_t bytes = [MiransasCleanup recursiveSizeAtPath:path];
                NSString *baseName = [path lastPathComponent];
                NSString *parent = [path stringByDeletingLastPathComponent];
                NSString *displayParent = abbreviate_home_path(parent, homePath);

                MiransasCleanupEntry *e = [[MiransasCleanupEntry alloc] init];
                e.path = path;
                e.name = baseName;
                e.bytes = bytes;
                e.detail = [NSString stringWithFormat:@"%@  ·  Modified %@",
                            displayParent, [MiransasCleanup formatRelativeDate:mtime]];
                [out addObject:e];
                [e release];
            }

            if (progress) {
                NSTimeInterval nowT = [NSDate timeIntervalSinceReferenceDate];
                if (nowT - lastProgressTime > 0.15 || (i + 1) == total) {
                    lastProgressTime = nowT;
                    progress(i + 1, total);
                }
            }
        }
    }

    [out sortUsingComparator:^NSComparisonResult(MiransasCleanupEntry *a,
                                                  MiransasCleanupEntry *b) {
        if (b.bytes > a.bytes) return NSOrderedDescending;
        if (b.bytes < a.bytes) return NSOrderedAscending;
        return [a.name caseInsensitiveCompare:b.name];
    }];
    return [[out copy] autorelease];
}

@implementation MiransasCleanup

+ (uint64_t)recursiveSizeAtPath:(NSString *)path {
    if (!path) return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
    if (!attrs) return 0;
    NSString *type = [attrs fileType];
    if ([type isEqualToString:NSFileTypeRegular]) {
        return [attrs fileSize];
    }
    if (![type isEqualToString:NSFileTypeDirectory]) {
        return 0;
    }
    NSURL *url = [NSURL fileURLWithPath:path];
    NSDirectoryEnumerator *e =
        [fm enumeratorAtURL:url
   includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLIsRegularFileKey]
                      options:NSDirectoryEnumerationSkipsHiddenFiles
                 errorHandler:^BOOL(NSURL *u, NSError *err) {
                     (void)u; (void)err;
                     return YES;
                 }];
    uint64_t total = 0;
    for (NSURL *u in e) {
        NSNumber *isFile = nil;
        if (![u getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:NULL]) continue;
        if (!isFile.boolValue) continue;
        NSNumber *sz = nil;
        if ([u getResourceValue:&sz forKey:NSURLFileSizeKey error:NULL] && sz) {
            total += sz.unsignedLongLongValue;
        }
    }
    return total;
}

+ (NSString *)formatBytes:(uint64_t)bytes {
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes
                                          countStyle:NSByteCountFormatterCountStyleFile];
}

+ (NSString *)formatRelativeDate:(NSDate *)date {
    if (!date) return @"unknown";
    NSTimeInterval ago = [[NSDate date] timeIntervalSinceDate:date];
    if (ago < 0) ago = 0;
    if (ago < 60) return @"just now";
    if (ago < 3600) {
        int m = (int)(ago / 60);
        return [NSString stringWithFormat:@"%d minute%s ago", m, m == 1 ? "" : "s"];
    }
    if (ago < 86400) {
        int h = (int)(ago / 3600);
        return [NSString stringWithFormat:@"%d hour%s ago", h, h == 1 ? "" : "s"];
    }
    if (ago < 86400 * 30) {
        int d = (int)(ago / 86400);
        return [NSString stringWithFormat:@"%d day%s ago", d, d == 1 ? "" : "s"];
    }
    if (ago < 86400 * 365) {
        int mo = (int)(ago / (86400 * 30));
        return [NSString stringWithFormat:@"%d month%s ago", mo, mo == 1 ? "" : "s"];
    }
    int y = (int)(ago / (86400 * 365));
    return [NSString stringWithFormat:@"%d year%s ago", y, y == 1 ? "" : "s"];
}

+ (NSArray<MiransasCleanupEntry *> *)cachedCacheEntries {
    @synchronized(self) {
        if (!gCachedEntries) return nil;
        if (!gCachedEntriesTimestamp ||
            [[NSDate date] timeIntervalSinceDate:gCachedEntriesTimestamp] > 300.0) {
            return nil;
        }
        return [[gCachedEntries retain] autorelease];
    }
}

+ (void)invalidateCacheEntriesCache {
    @synchronized(self) {
        [gCachedEntries release];
        gCachedEntries = nil;
        [gCachedEntriesTimestamp release];
        gCachedEntriesTimestamp = nil;
    }
}

+ (void)loadCacheEntriesWithCompletion:(void (^)(NSArray<MiransasCleanupEntry *> *))completion {
    NSArray *fresh = [self cachedCacheEntries];
    if (fresh) {
        if (completion) completion(fresh);
        return;
    }

    void (^cb)(NSArray *) = completion ? [completion copy] : nil;

    @synchronized(self) {
        if (gCacheScanInFlight) {
            if (!gCacheScanWaiters) gCacheScanWaiters = [[NSMutableArray alloc] init];
            if (cb) [gCacheScanWaiters addObject:cb];
            if (cb) [cb release];
            return;
        }
        gCacheScanInFlight = YES;
        if (!gCacheScanWaiters) gCacheScanWaiters = [[NSMutableArray alloc] init];
        if (cb) [gCacheScanWaiters addObject:cb];
        if (cb) [cb release];
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSString *caches = [NSHomeDirectory()
                                stringByAppendingPathComponent:@"Library/Caches"];
            NSArray *snapshot = scan_top_level_entries(caches, NO);

            NSArray *waiters = nil;
            @synchronized([MiransasCleanup class]) {
                [gCachedEntries release];
                gCachedEntries = [snapshot retain];
                [gCachedEntriesTimestamp release];
                gCachedEntriesTimestamp = [[NSDate date] retain];
                gCacheScanInFlight = NO;
                waiters = [gCacheScanWaiters copy];
                [gCacheScanWaiters removeAllObjects];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                for (void (^w)(NSArray *) in waiters) {
                    w(snapshot);
                }
                [waiters release];
            });
        }
    });
}

+ (NSArray<MiransasCleanupEntry *> *)cachedDownloadsEntries {
    @synchronized(self) {
        if (!gCachedDownloads) return nil;
        if (!gCachedDownloadsTimestamp ||
            [[NSDate date] timeIntervalSinceDate:gCachedDownloadsTimestamp] > 300.0) {
            return nil;
        }
        return [[gCachedDownloads retain] autorelease];
    }
}

+ (void)invalidateDownloadsEntriesCache {
    @synchronized(self) {
        [gCachedDownloads release];
        gCachedDownloads = nil;
        [gCachedDownloadsTimestamp release];
        gCachedDownloadsTimestamp = nil;
    }
}

+ (void)loadDownloadsEntriesWithCompletion:(void (^)(NSArray<MiransasCleanupEntry *> *))completion {
    NSArray *fresh = [self cachedDownloadsEntries];
    if (fresh) {
        if (completion) completion(fresh);
        return;
    }

    void (^cb)(NSArray *) = completion ? [completion copy] : nil;

    @synchronized(self) {
        if (gDownloadsScanInFlight) {
            if (!gDownloadsScanWaiters) gDownloadsScanWaiters = [[NSMutableArray alloc] init];
            if (cb) [gDownloadsScanWaiters addObject:cb];
            if (cb) [cb release];
            return;
        }
        gDownloadsScanInFlight = YES;
        if (!gDownloadsScanWaiters) gDownloadsScanWaiters = [[NSMutableArray alloc] init];
        if (cb) [gDownloadsScanWaiters addObject:cb];
        if (cb) [cb release];
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSString *downloads = [NSHomeDirectory()
                                   stringByAppendingPathComponent:@"Downloads"];
            NSArray *snapshot = scan_top_level_entries(downloads, YES);

            NSArray *waiters = nil;
            @synchronized([MiransasCleanup class]) {
                [gCachedDownloads release];
                gCachedDownloads = [snapshot retain];
                [gCachedDownloadsTimestamp release];
                gCachedDownloadsTimestamp = [[NSDate date] retain];
                gDownloadsScanInFlight = NO;
                waiters = [gDownloadsScanWaiters copy];
                [gDownloadsScanWaiters removeAllObjects];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                for (void (^w)(NSArray *) in waiters) {
                    w(snapshot);
                }
                [waiters release];
            });
        }
    });
}

+ (NSArray<MiransasCleanupEntry *> *)cachedLargeFilesEntries {
    @synchronized(self) {
        if (!gCachedLargeFiles) return nil;
        if (!gCachedLargeFilesTimestamp ||
            [[NSDate date] timeIntervalSinceDate:gCachedLargeFilesTimestamp] > 300.0) {
            return nil;
        }
        return [[gCachedLargeFiles retain] autorelease];
    }
}

+ (void)invalidateLargeFilesEntriesCache {
    @synchronized(self) {
        [gCachedLargeFiles release];
        gCachedLargeFiles = nil;
        [gCachedLargeFilesTimestamp release];
        gCachedLargeFilesTimestamp = nil;
    }
}

+ (void)loadLargeFilesEntriesWithCompletion:(void (^)(NSArray<MiransasCleanupEntry *> *))completion {
    NSArray *fresh = [self cachedLargeFilesEntries];
    if (fresh) {
        if (completion) completion(fresh);
        return;
    }

    void (^cb)(NSArray *) = completion ? [completion copy] : nil;

    @synchronized(self) {
        if (gLargeFilesScanInFlight) {
            if (!gLargeFilesScanWaiters) gLargeFilesScanWaiters = [[NSMutableArray alloc] init];
            if (cb) [gLargeFilesScanWaiters addObject:cb];
            if (cb) [cb release];
            return;
        }
        gLargeFilesScanInFlight = YES;
        if (!gLargeFilesScanWaiters) gLargeFilesScanWaiters = [[NSMutableArray alloc] init];
        if (cb) [gLargeFilesScanWaiters addObject:cb];
        if (cb) [cb release];
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            const uint64_t threshold = 100ULL * 1024ULL * 1024ULL;
            NSArray *snapshot = scan_large_files(NSHomeDirectory(), threshold);

            NSArray *waiters = nil;
            @synchronized([MiransasCleanup class]) {
                [gCachedLargeFiles release];
                gCachedLargeFiles = [snapshot retain];
                [gCachedLargeFilesTimestamp release];
                gCachedLargeFilesTimestamp = [[NSDate date] retain];
                gLargeFilesScanInFlight = NO;
                waiters = [gLargeFilesScanWaiters copy];
                [gLargeFilesScanWaiters removeAllObjects];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                for (void (^w)(NSArray *) in waiters) {
                    w(snapshot);
                }
                [waiters release];
            });
        }
    });
}

+ (NSArray<MiransasCleanupEntry *> *)cachedStaleArtifactsEntries {
    @synchronized(self) {
        if (!gCachedStaleArtifacts) return nil;
        if (!gCachedStaleArtifactsTimestamp ||
            [[NSDate date] timeIntervalSinceDate:gCachedStaleArtifactsTimestamp] > 300.0) {
            return nil;
        }
        return [[gCachedStaleArtifacts retain] autorelease];
    }
}

+ (void)invalidateStaleArtifactsEntriesCache {
    @synchronized(self) {
        [gCachedStaleArtifacts release];
        gCachedStaleArtifacts = nil;
        [gCachedStaleArtifactsTimestamp release];
        gCachedStaleArtifactsTimestamp = nil;
    }
}

+ (void)loadStaleArtifactsEntriesWithProgress:(void (^)(NSUInteger, NSUInteger))progress
                                   completion:(void (^)(NSArray<MiransasCleanupEntry *> *))completion {
    NSArray *fresh = [self cachedStaleArtifactsEntries];
    if (fresh) {
        if (completion) completion(fresh);
        return;
    }

    void (^cb)(NSArray *) = completion ? [completion copy] : nil;
    void (^pb)(NSUInteger, NSUInteger) = progress ? [progress copy] : nil;

    @synchronized(self) {
        if (gStaleArtifactsScanInFlight) {
            if (!gStaleArtifactsScanWaiters) gStaleArtifactsScanWaiters = [[NSMutableArray alloc] init];
            if (cb) [gStaleArtifactsScanWaiters addObject:cb];
            if (cb) [cb release];
            if (pb) [pb release];
            return;
        }
        gStaleArtifactsScanInFlight = YES;
        if (!gStaleArtifactsScanWaiters) gStaleArtifactsScanWaiters = [[NSMutableArray alloc] init];
        if (cb) [gStaleArtifactsScanWaiters addObject:cb];
        if (cb) [cb release];
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            const NSTimeInterval threshold = 30.0 * 86400.0;
            void (^bgProgress)(NSUInteger, NSUInteger) = nil;
            if (pb) {
                bgProgress = ^(NSUInteger checked, NSUInteger total) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        pb(checked, total);
                    });
                };
            }
            NSArray *snapshot = scan_stale_artifacts(NSHomeDirectory(),
                                                     threshold,
                                                     bgProgress);

            NSArray *waiters = nil;
            @synchronized([MiransasCleanup class]) {
                [gCachedStaleArtifacts release];
                gCachedStaleArtifacts = [snapshot retain];
                [gCachedStaleArtifactsTimestamp release];
                gCachedStaleArtifactsTimestamp = [[NSDate date] retain];
                gStaleArtifactsScanInFlight = NO;
                waiters = [gStaleArtifactsScanWaiters copy];
                [gStaleArtifactsScanWaiters removeAllObjects];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                for (void (^w)(NSArray *) in waiters) {
                    w(snapshot);
                }
                [waiters release];
                if (pb) [pb release];
            });
        }
    });
}

+ (void)moveURLsToTrash:(NSArray<NSURL *> *)urls
             completion:(void (^)(NSUInteger, uint64_t, NSError *))completion {
    if (urls.count == 0) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(0, 0, nil); });
        }
        return;
    }

    void (^cb)(NSUInteger, uint64_t, NSError *) = completion ? [completion copy] : nil;
    NSArray<NSURL *> *urlsCopy = [urls copy];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            uint64_t totalBytes = 0;
            for (NSURL *u in urlsCopy) {
                totalBytes += [MiransasCleanup recursiveSizeAtPath:u.path];
            }
            [[NSWorkspace sharedWorkspace] recycleURLs:urlsCopy
                completionHandler:^(NSDictionary<NSURL *,NSURL *> *newURLs, NSError *error) {
                NSUInteger n = newURLs.count;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (cb) {
                        cb(n, totalBytes, error);
                        [cb release];
                    }
                });
            }];
            [urlsCopy release];
        }
    });
}

@end

#pragma mark - Cleanup card

@implementation MiransasCleanupCard {
    NSImageView *_iconView;
    NSTextField *_titleField;
    NSTextField *_descField;
    NSImageView *_emptyStateIcon;
    NSTextField *_statsField;
    NSButton *_actionButton;
    NSProgressIndicator *_spinner;
    NSTrackingArea *_hoverArea;
    BOOL _hovering;
}

- (instancetype)initWithTitle:(NSString *)title
                       symbol:(NSString *)symbolName
                  description:(NSString *)description
                  actionTitle:(NSString *)actionTitle {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 8.0;
    self.layer.borderWidth = 1.0;
    [self refreshChromeColors];

    _iconView = [[NSImageView alloc] init];
    [_iconView setImageScaling:NSImageScaleProportionallyUpOrDown];
    if (@available(macOS 11.0, *)) {
        _iconView.image = [NSImage imageWithSystemSymbolName:symbolName
                                    accessibilityDescription:nil];
        _iconView.contentTintColor = [NSColor systemOrangeColor];
    }
    [self addSubview:_iconView];

    _titleField = [[NSTextField alloc] init];
    [_titleField setBezeled:NO];
    [_titleField setDrawsBackground:NO];
    [_titleField setEditable:NO];
    [_titleField setSelectable:NO];
    [_titleField setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold]];
    [_titleField setTextColor:[NSColor labelColor]];
    [_titleField setStringValue:[title uppercaseString]];
    [self addSubview:_titleField];

    _descField = [[NSTextField alloc] init];
    [_descField setBezeled:NO];
    [_descField setDrawsBackground:NO];
    [_descField setEditable:NO];
    [_descField setSelectable:NO];
    [_descField setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular]];
    [_descField setTextColor:[NSColor secondaryLabelColor]];
    [_descField setStringValue:description ?: @""];
    [[_descField cell] setWraps:YES];
    [[_descField cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [self addSubview:_descField];

    _emptyStateIcon = [[NSImageView alloc] init];
    [_emptyStateIcon setImageScaling:NSImageScaleProportionallyUpOrDown];
    if (@available(macOS 11.0, *)) {
        _emptyStateIcon.contentTintColor = [NSColor systemGrayColor];
    }
    [_emptyStateIcon setHidden:YES];
    [self addSubview:_emptyStateIcon];

    _statsField = [[NSTextField alloc] init];
    [_statsField setBezeled:NO];
    [_statsField setDrawsBackground:NO];
    [_statsField setEditable:NO];
    [_statsField setSelectable:NO];
    [_statsField setFont:[NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular]];
    [_statsField setTextColor:[NSColor secondaryLabelColor]];
    [_statsField setStringValue:@"Scanning…"];
    [self addSubview:_statsField];

    _actionButton = [[MiransasBezeledButton alloc] initWithFrame:NSZeroRect];
    [_actionButton setTitle:actionTitle ?: @""];
    [_actionButton setTarget:self];
    [_actionButton setAction:@selector(actionPressed:)];
    miransas_style_button(_actionButton);
    [self addSubview:_actionButton];

    _spinner = [[NSProgressIndicator alloc] init];
    [_spinner setStyle:NSProgressIndicatorStyleSpinning];
    [_spinner setControlSize:NSControlSizeSmall];
    [_spinner setDisplayedWhenStopped:NO];
    [_spinner setIndeterminate:YES];
    [self addSubview:_spinner];

    return self;
}

- (void)refreshChromeColors {
    NSColor *bg = [[NSColor labelColor] colorWithAlphaComponent:0.05];
    NSColor *border = [NSColor separatorColor];
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = bg.CGColor;
        self.layer.borderColor     = border.CGColor;
    }];
}

- (void)dealloc {
    [_onAction release];
    [_hoverArea release];
    [super dealloc];
}

- (void)actionPressed:(NSButton *)sender {
    (void)sender;
    if (self.onAction) self.onAction();
}

- (void)setStatsText:(NSString *)text {
    [_statsField setStringValue:text ?: @""];
}

- (void)setEmptyStateSymbol:(NSString *)symbolName {
    BOOL empty = symbolName.length > 0;
    if (@available(macOS 11.0, *)) {
        if (!empty) {
            _emptyStateIcon.image = nil;
            [_emptyStateIcon setHidden:YES];
        } else {
            // Configure the symbol at a large point size so contentTintColor
            // is applied to a properly hinted vector glyph.
            NSImage *img = [NSImage
                imageWithSystemSymbolName:symbolName
                 accessibilityDescription:nil];
            NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration
                configurationWithPointSize:24.0
                                    weight:NSFontWeightRegular];
            _emptyStateIcon.image = [img imageWithSymbolConfiguration:cfg];
            _emptyStateIcon.contentTintColor = [NSColor systemGrayColor];
            [_emptyStateIcon setHidden:NO];
        }
    }
    // Hide the description in the empty state — the icon + stats text
    // becomes the entire body of the card.
    [_descField setHidden:empty];
    // Center the stats text under the icon when empty, left-align otherwise.
    [_statsField setAlignment:empty ? NSTextAlignmentCenter
                                    : NSTextAlignmentLeft];
    [self setNeedsLayout:YES];
}

- (void)setActionPrimary:(BOOL)primary {
    [_actionButton setBezelColor:primary ? [NSColor controlAccentColor]
                                         : nil];
}

- (void)setActionEnabled:(BOOL)enabled {
    [_actionButton setEnabled:enabled];
}

- (void)setActionHidden:(BOOL)hidden {
    [_actionButton setHidden:hidden];
}

- (void)setActionTitle:(NSString *)title {
    [_actionButton setTitle:title ?: @""];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self refreshChromeColors];
    [self setNeedsDisplay:YES];
}

- (void)setScanning:(BOOL)scanning {
    if (scanning) {
        [_actionButton setHidden:YES];
        [_spinner startAnimation:nil];
    } else {
        [_spinner stopAnimation:nil];
        [_actionButton setHidden:NO];
    }
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_hoverArea) {
        [self removeTrackingArea:_hoverArea];
        [_hoverArea release];
        _hoverArea = nil;
    }
    NSTrackingAreaOptions opts = NSTrackingMouseEnteredAndExited
                               | NSTrackingActiveInActiveApp
                               | NSTrackingInVisibleRect;
    _hoverArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                              options:opts
                                                owner:self
                                             userInfo:nil];
    [self addTrackingArea:_hoverArea];
}

- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    if (_hovering) return;
    _hovering = YES;
    [self applyHoverShadow:YES];
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    if (!_hovering) return;
    _hovering = NO;
    [self applyHoverShadow:NO];
}

- (void)applyHoverShadow:(BOOL)on {
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.15];
    if (on) {
        self.layer.shadowOffset = CGSizeMake(0.0, -2.0);
        self.layer.shadowRadius = 4.0;
        self.layer.shadowOpacity = 0.18f;
        self.layer.shadowColor = [[NSColor blackColor] CGColor];
    } else {
        self.layer.shadowOpacity = 0.0f;
    }
    [CATransaction commit];
}

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat pad = 14.0;
    CGFloat iconSide = 22.0;
    CGFloat btnW = 160.0;
    CGFloat btnH = 24.0;

    _iconView.frame = NSMakeRect(pad, b.size.height - pad - iconSide,
                                 iconSide, iconSide);

    CGFloat titleX = pad + iconSide + 8.0;
    CGFloat titleY = b.size.height - pad - 16.0;
    _titleField.frame = NSMakeRect(titleX, titleY,
                                   b.size.width - titleX - pad, 16.0);

    CGFloat btnX = b.size.width - pad - btnW;
    CGFloat btnY = pad;
    _actionButton.frame = NSMakeRect(btnX, btnY, btnW, btnH);

    CGFloat spinSize = 16.0;
    _spinner.frame = NSMakeRect(btnX + (btnW - spinSize) / 2.0,
                                btnY + (btnH - spinSize) / 2.0,
                                spinSize, spinSize);

    BOOL emptyState = !_emptyStateIcon.isHidden;
    if (!emptyState) {
        // Standard layout: description in the middle, stats text in the
        // bottom row left-aligned, next to the action button.
        CGFloat descY = titleY - 6.0 - 32.0;
        _descField.frame = NSMakeRect(pad, descY,
                                      b.size.width - 2 * pad, 32.0);
        CGFloat statsY = btnY + (btnH - 17.0) / 2.0;
        _statsField.frame = NSMakeRect(pad, statsY,
                                       btnX - pad - 12.0, 17.0);
        return;
    }

    // Empty state: vertical stack of [icon, gap, text], horizontally
    // centered in the area to the left of the action button (or full width
    // when the button is hidden) and vertically centered in the body area
    // between the title and the bottom padding.
    CGFloat iconSize = 24.0;
    CGFloat gap = 8.0;
    CGFloat textH = 17.0;
    CGFloat stackH = iconSize + gap + textH;

    CGFloat areaTop = titleY - 6.0;
    CGFloat areaBottom = pad;
    CGFloat areaH = areaTop - areaBottom;
    CGFloat stackBottom = areaBottom + (areaH - stackH) / 2.0;
    if (stackBottom < areaBottom) stackBottom = areaBottom;

    CGFloat availLeft = pad;
    CGFloat availRight = _actionButton.isHidden
        ? (b.size.width - pad)
        : (btnX - 12.0);
    CGFloat availW = availRight - availLeft;
    if (availW < iconSize) availW = iconSize;

    CGFloat textY = stackBottom;
    CGFloat iconY = textY + textH + gap;

    _statsField.frame = NSMakeRect(availLeft, textY, availW, textH);
    _emptyStateIcon.frame = NSMakeRect(
        availLeft + (availW - iconSize) / 2.0,
        iconY, iconSize, iconSize);
}

@end

#pragma mark - Review sheet

@interface MiransasCleanupSheet () <NSWindowDelegate>
@end

@implementation MiransasCleanupSheet {
    NSString *_title;
    NSString *_subtitle;
    NSArray<MiransasCleanupEntry *> *_entries;
    NSString *_extraWarning;

    NSWindow *_sheetWindow;
    NSWindow *_parentWindow;
    NSScrollView *_scrollView;
    MiransasFlippedView *_listContent;
    NSTextField *_statsField;
    NSButton *_actionButton;
    NSButton *_cancelButton;
    NSButton *_selectAllButton;
    NSMutableArray<NSButton *> *_checkboxes;

    void (^_doneBlock)(BOOL, NSUInteger, uint64_t);
    BOOL _busy;
}

- (instancetype)initWithTitle:(NSString *)title
                     subtitle:(NSString *)subtitle
                      entries:(NSArray<MiransasCleanupEntry *> *)entries
                 extraWarning:(NSString *)extraWarning {
    self = [super init];
    if (!self) return nil;
    _title = [title copy];
    _subtitle = [subtitle copy];
    _entries = [entries copy];
    _extraWarning = [extraWarning copy];
    _checkboxes = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc {
    [_title release];
    [_subtitle release];
    [_entries release];
    [_extraWarning release];
    [_checkboxes release];
    [_sheetWindow release];
    [_doneBlock release];
    [super dealloc];
}

#pragma mark Build

- (NSTextField *)makeLabel:(NSString *)s
                      size:(CGFloat)sz
                    weight:(NSFontWeight)w
                     color:(NSColor *)c {
    NSTextField *f = [[[NSTextField alloc] init] autorelease];
    [f setBezeled:NO];
    [f setDrawsBackground:NO];
    [f setEditable:NO];
    [f setSelectable:NO];
    [f setStringValue:s ?: @""];
    [f setFont:[NSFont systemFontOfSize:sz weight:w]];
    [f setTextColor:c];
    return f;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0.0, 0.0, 560.0, 480.0);
    _sheetWindow = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [_sheetWindow setReleasedWhenClosed:NO];
    [_sheetWindow setDelegate:self];
    [_sheetWindow setTitle:_title ?: @"Cleanup"];
    [_sheetWindow setMinSize:NSMakeSize(440.0, 320.0)];

    NSView *root = [_sheetWindow contentView];
    CGFloat pad = 18.0;
    CGFloat innerW = frame.size.width - 2.0 * pad;

    CGFloat y = frame.size.height - pad;

    // Subtitle
    NSTextField *subtitle = [self makeLabel:_subtitle
                                       size:13.0
                                     weight:NSFontWeightRegular
                                      color:[NSColor secondaryLabelColor]];
    [[subtitle cell] setWraps:YES];
    y -= 32.0;
    subtitle.frame = NSMakeRect(pad, y, innerW, 32.0);
    [subtitle setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [root addSubview:subtitle];

    // Select all button
    y -= 8.0 + 24.0;
    _selectAllButton = [[[MiransasBezeledButton alloc]
                         initWithFrame:NSZeroRect] autorelease];
    [_selectAllButton setTitle:@"Select All"];
    [_selectAllButton setTarget:self];
    [_selectAllButton setAction:@selector(toggleAll:)];
    miransas_style_button(_selectAllButton);
    _selectAllButton.frame = NSMakeRect(pad, y, 110.0, 24.0);
    [_selectAllButton setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
    [root addSubview:_selectAllButton];

    // Scroll view
    CGFloat footerH = 60.0;
    CGFloat listY = pad + footerH;
    CGFloat listH = y - 8.0 - listY;

    _scrollView = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(pad, listY, innerW, listH)];
    [_scrollView setBorderType:NSBezelBorder];
    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setAutohidesScrollers:YES];
    [_scrollView setDrawsBackground:YES];
    [_scrollView setAutoresizingMask:
        NSViewWidthSizable | NSViewHeightSizable];
    [root addSubview:_scrollView];

    // List content (flipped so y=0 is top)
    _listContent = [[MiransasFlippedView alloc]
        initWithFrame:NSMakeRect(0.0, 0.0, innerW - 2.0, 0.0)];
    [_listContent setAutoresizingMask:NSViewWidthSizable];
    [_scrollView setDocumentView:_listContent];
    [_listContent release];

    [self rebuildList];

    // Stats footer
    _statsField = [self makeLabel:@""
                              size:13.0
                            weight:NSFontWeightRegular
                             color:[NSColor labelColor]];
    _statsField.frame = NSMakeRect(pad, pad + 28.0,
                                   innerW - 260.0, 18.0);
    [_statsField setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [root addSubview:_statsField];

    // Cancel + action buttons
    CGFloat btnH = 28.0;
    CGFloat actionW = 200.0;
    CGFloat cancelW = 90.0;
    CGFloat gap = 10.0;

    _cancelButton = [[[MiransasBezeledButton alloc]
                      initWithFrame:NSZeroRect] autorelease];
    [_cancelButton setTitle:@"Cancel"];
    [_cancelButton setTarget:self];
    [_cancelButton setAction:@selector(cancelPressed:)];
    miransas_style_button(_cancelButton);
    [_cancelButton setKeyEquivalent:@"\e"];
    _cancelButton.frame = NSMakeRect(frame.size.width - pad - actionW - gap - cancelW,
                                     pad, cancelW, btnH);
    [_cancelButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
    [root addSubview:_cancelButton];

    _actionButton = [[[MiransasBezeledButton alloc]
                      initWithFrame:NSZeroRect] autorelease];
    [_actionButton setTitle:@"Move Selected to Trash"];
    [_actionButton setTarget:self];
    [_actionButton setAction:@selector(actionPressed:)];
    miransas_style_button(_actionButton);
    [_actionButton setKeyEquivalent:@"\r"];
    // Primary action uses the system accent color — distinguishes the
    // destructive confirm from Cancel/Select-All.
    [_actionButton setBezelColor:[NSColor controlAccentColor]];
    _actionButton.frame = NSMakeRect(frame.size.width - pad - actionW,
                                     pad, actionW, btnH);
    [_actionButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
    [root addSubview:_actionButton];

    [self updateStats];
}

- (void)rebuildList {
    for (NSView *sub in [[[_listContent subviews] copy] autorelease]) {
        [sub removeFromSuperview];
    }
    [_checkboxes removeAllObjects];

    NSRect docFrame = _listContent.frame;
    docFrame.size.width = _scrollView.contentSize.width;
    if (docFrame.size.width < 200.0) docFrame.size.width = 540.0;

    CGFloat rowH = 36.0;
    CGFloat pad = 8.0;
    CGFloat y = pad;
    NSUInteger idx = 0;

    for (MiransasCleanupEntry *entry in _entries) {
        NSView *row = [[NSView alloc]
            initWithFrame:NSMakeRect(0.0, y, docFrame.size.width, rowH)];
        [row setAutoresizingMask:NSViewWidthSizable];

        NSButton *cb = [NSButton checkboxWithTitle:@""
                                            target:self
                                            action:@selector(checkboxToggled:)];
        cb.tag = (NSInteger)idx;
        cb.state = entry.selected ? NSControlStateValueOn : NSControlStateValueOff;
        cb.frame = NSMakeRect(10.0, (rowH - 18.0) / 2.0, 22.0, 18.0);
        [row addSubview:cb];
        [_checkboxes addObject:cb];

        NSTextField *name = [self makeLabel:entry.name
                                       size:13.0
                                     weight:NSFontWeightMedium
                                      color:[NSColor labelColor]];
        [[name cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
        CGFloat nameX = 38.0;
        CGFloat sizeW = 110.0;
        CGFloat rightInset = 12.0;
        CGFloat nameW = docFrame.size.width - nameX - sizeW - rightInset - 6.0;
        if (nameW < 80.0) nameW = 80.0;
        name.frame = NSMakeRect(nameX, rowH / 2.0 + 1.0, nameW, 14.0);
        [name setAutoresizingMask:NSViewWidthSizable];
        [row addSubview:name];

        NSTextField *detail = [self makeLabel:entry.detail
                                         size:11.0
                                       weight:NSFontWeightRegular
                                        color:[NSColor tertiaryLabelColor]];
        detail.frame = NSMakeRect(nameX, rowH / 2.0 - 14.0, nameW, 13.0);
        [detail setAutoresizingMask:NSViewWidthSizable];
        [row addSubview:detail];

        NSTextField *sz = [self makeLabel:[MiransasCleanup formatBytes:entry.bytes]
                                     size:13.0
                                   weight:NSFontWeightRegular
                                    color:[NSColor labelColor]];
        [sz setAlignment:NSTextAlignmentRight];
        [sz setFont:[NSFont monospacedDigitSystemFontOfSize:13.0
                                                     weight:NSFontWeightRegular]];
        sz.frame = NSMakeRect(docFrame.size.width - sizeW - rightInset,
                              (rowH - 16.0) / 2.0, sizeW, 16.0);
        [sz setAutoresizingMask:NSViewMinXMargin];
        [row addSubview:sz];

        [_listContent addSubview:row];
        [row release];

        y += rowH;
        idx++;
    }

    docFrame.size.height = y + pad;
    if (docFrame.size.height < _scrollView.contentSize.height) {
        docFrame.size.height = _scrollView.contentSize.height;
    }
    [_listContent setFrame:docFrame];
}

#pragma mark Actions

- (void)checkboxToggled:(NSButton *)cb {
    NSInteger i = cb.tag;
    if ((NSUInteger)i >= _entries.count) return;
    MiransasCleanupEntry *e = _entries[i];
    e.selected = (cb.state == NSControlStateValueOn);
    [self updateStats];
}

- (void)toggleAll:(NSButton *)sender {
    (void)sender;
    BOOL anyOff = NO;
    for (MiransasCleanupEntry *e in _entries) {
        if (!e.selected) { anyOff = YES; break; }
    }
    NSControlStateValue newState =
        anyOff ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSUInteger i = 0; i < _entries.count; i++) {
        _entries[i].selected = anyOff;
        if (i < _checkboxes.count) {
            _checkboxes[i].state = newState;
        }
    }
    [_selectAllButton setTitle:anyOff ? @"Deselect All" : @"Select All"];
    [self updateStats];
}

- (void)updateStats {
    uint64_t bytes = 0;
    NSUInteger count = 0;
    for (MiransasCleanupEntry *e in _entries) {
        if (e.selected) { bytes += e.bytes; count++; }
    }
    if (count == 0) {
        [_statsField setStringValue:
            [NSString stringWithFormat:@"%lu item%s · none selected",
                                       (unsigned long)_entries.count,
                                       _entries.count == 1 ? "" : "s"]];
    } else {
        [_statsField setStringValue:
            [NSString stringWithFormat:@"%lu of %lu selected · %@",
                                       (unsigned long)count,
                                       (unsigned long)_entries.count,
                                       [MiransasCleanup formatBytes:bytes]]];
    }
    [_actionButton setEnabled:(count > 0 && !_busy)];
    [_selectAllButton setEnabled:!_busy];
}

- (void)cancelPressed:(NSButton *)sender {
    (void)sender;
    if (_busy) return;
    [self closeWithDidTrash:NO count:0 bytes:0];
}

- (void)actionPressed:(NSButton *)sender {
    (void)sender;
    if (_busy) return;

    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    uint64_t bytes = 0;
    NSUInteger count = 0;
    for (MiransasCleanupEntry *e in _entries) {
        if (e.selected) {
            [urls addObject:[NSURL fileURLWithPath:e.path]];
            bytes += e.bytes;
            count++;
        }
    }
    if (urls.count == 0) return;

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:
        [NSString stringWithFormat:@"Move %lu item%s to Trash?",
                                   (unsigned long)count, count == 1 ? "" : "s"]];
    NSMutableString *info = [NSMutableString stringWithFormat:
        @"Approximately %@ will be reclaimed.",
        [MiransasCleanup formatBytes:bytes]];
    if (_extraWarning.length > 0) {
        [info appendString:@"\n\n"];
        [info appendString:_extraWarning];
    }
    [info appendString:
        @"\n\nItems will be moved to the Trash, not permanently deleted."];
    [alert setInformativeText:info];
    [alert addButtonWithTitle:@"Move to Trash"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert setAlertStyle:NSAlertStyleWarning];

    [alert beginSheetModalForWindow:_sheetWindow
                  completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        [self performTrash:urls];
    }];
}

- (void)performTrash:(NSArray<NSURL *> *)urls {
    _busy = YES;
    [_actionButton setEnabled:NO];
    [_cancelButton setEnabled:NO];
    [_selectAllButton setEnabled:NO];
    [_statsField setStringValue:@"Moving to Trash…"];

    [MiransasCleanup moveURLsToTrash:urls
                          completion:^(NSUInteger n, uint64_t b, NSError *err) {
        if (err) {
            NSAlert *e = [[[NSAlert alloc] init] autorelease];
            [e setMessageText:@"Some items could not be moved"];
            [e setInformativeText:[err localizedDescription] ?: @"Unknown error"];
            [e setAlertStyle:NSAlertStyleWarning];
            [e beginSheetModalForWindow:_sheetWindow
                      completionHandler:^(NSModalResponse r) {
                (void)r;
                [self closeWithDidTrash:(n > 0) count:n bytes:b];
            }];
        } else {
            [self closeWithDidTrash:YES count:n bytes:b];
        }
    }];
}

- (void)closeWithDidTrash:(BOOL)didTrash
                    count:(NSUInteger)count
                    bytes:(uint64_t)bytes {
    if (_parentWindow) {
        [_parentWindow endSheet:_sheetWindow returnCode:NSModalResponseStop];
    } else {
        [_sheetWindow close];
    }
    if (_doneBlock) {
        _doneBlock(didTrash, count, bytes);
    }
}

- (void)windowWillClose:(NSNotification *)note {
    (void)note;
    if (_doneBlock && !_busy) {
        // Closed by window close button or external close
    }
}

- (void)beginSheetForWindow:(NSWindow *)parent
                 completion:(void (^)(BOOL, NSUInteger, uint64_t))completion {
    if (!_sheetWindow) [self buildWindow];
    _parentWindow = parent;
    [_doneBlock release];
    _doneBlock = completion ? [completion copy] : nil;

    [parent beginSheet:_sheetWindow
     completionHandler:^(NSModalResponse code) {
         (void)code;
     }];
}

@end
