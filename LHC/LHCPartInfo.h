//
//  LHCPartInfo.h
//  LHC Interactive
//
//  Lightweight educational metadata attached to a clickable scene part.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LHCPartInfo : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *category;
@property (nonatomic, copy, readonly) NSString *summary;
@property (nonatomic, copy, readonly) NSArray<NSString *> *facts;
@property (nonatomic, strong, readonly) NSColor *accentColor;
@property (nonatomic, readonly, getter=isDetector) BOOL detector;

- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                          category:(NSString *)category
                           summary:(NSString *)summary
                             facts:(NSArray<NSString *> *)facts
                       accentColor:(NSColor *)accentColor
                          detector:(BOOL)isDetector NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
