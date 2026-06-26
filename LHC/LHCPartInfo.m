//
//  LHCPartInfo.m
//  LHC Interactive
//

#import "LHCPartInfo.h"

@implementation LHCPartInfo

- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                          category:(NSString *)category
                           summary:(NSString *)summary
                             facts:(NSArray<NSString *> *)facts
                       accentColor:(NSColor *)accentColor
                          detector:(BOOL)isDetector {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _name = [name copy];
        _category = [category copy];
        _summary = [summary copy];
        _facts = [facts copy];
        _accentColor = accentColor;
        _detector = isDetector;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<LHCPartInfo: %@ · %@>", self.identifier, self.name];
}

@end
