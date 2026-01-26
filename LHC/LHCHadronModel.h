//
//  LHCHadronModel.h
//  LHC Interactive
//
//  Model layer.  Procedurally constructs the complete LHC scene:
//  terrain, 27 km ring, colour-coded magnet lattice, four detectors,
//  proton bunches, camera, lighting and educational part metadata.
//

#import <Foundation/Foundation.h>
#import <SceneKit/SceneKit.h>
#import "LHCSimulationConfig.h"
#import "LHCPartInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface LHCHadronModel : NSObject

@property (nonatomic, strong, readonly) SCNScene *scene;
@property (nonatomic, strong, readonly) SCNNode *cameraNode;
@property (nonatomic, strong, readonly) SCNNode *terrainNode;
@property (nonatomic, strong, readonly) SCNNode *tunnelNode;
@property (nonatomic, strong, readonly) SCNNode *magnetsNode;
@property (nonatomic, strong, readonly) SCNNode *detectorsNode;
@property (nonatomic, strong, readonly) SCNNode *beamGroupA;
@property (nonatomic, strong, readonly) SCNNode *beamGroupB;
@property (nonatomic, strong, readonly) SCNNode *selectionNode;
@property (nonatomic, strong, readonly) NSDictionary<NSString *, LHCPartInfo *> *partCatalog;
@property (nonatomic, strong, readonly) NSArray<NSString *> *detectorIdentifiers;
@property (nonatomic, strong, readonly) LHCSimulationConfig *configuration;

@property (nonatomic, readonly) SCNVector3 initialCameraPosition;
@property (nonatomic, readonly) SCNVector3 cameraTarget;
@property (nonatomic, readonly) CGFloat initialFieldOfView;

- (instancetype)initWithConfiguration:(LHCSimulationConfig *)configuration NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)buildScene;
- (void)applyModelConfiguration:(LHCSimulationConfig *)configuration;

- (nullable LHCPartInfo *)partInfoForHitNode:(SCNNode *)node;
- (nullable SCNNode *)detectorNodeWithIdentifier:(NSString *)identifier;
- (SCNVector3)collisionPointForDetectorIdentifier:(NSString *)identifier;
- (SCNVector3)beamTangentForDetectorIdentifier:(NSString *)identifier;

- (void)highlightPartWithIdentifier:(nullable NSString *)identifier
                        accentColor:(nullable NSColor *)accentColor;
- (void)highlightNode:(nullable SCNNode *)partNode
           accentColor:(nullable NSColor *)accentColor;

- (void)advanceBeamsByRadians:(CGFloat)radians;
- (void)resetBeamPhase;
- (void)setBeamOpacity:(CGFloat)opacity;
- (void)applyBeamParticleCount:(NSInteger)count;

@end

NS_ASSUME_NONNULL_END
