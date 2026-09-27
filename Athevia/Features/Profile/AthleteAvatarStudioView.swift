import SwiftUI
import UIKit
import RealityKit
import simd

/// Production avatar presentation.
///
/// Validated appearance/loadout combinations resolve to high-resolution rendered
/// character assets. The vector construction remains only as a temporary fallback
/// while the production catalog is expanded.
private enum AvatarRenderAssetResolver {
    static func assetName(
        for avatar: AthleteAvatar,
        sport: Sport,
        pose: AvatarPose
    ) -> String? {
        let canonical = canonicalAssetName(
            for: avatar,
            sport: sport,
            pose: pose
        )

        if UIImage(named: canonical) != nil {
            return canonical
        }

        // Production-safe fallback: user-facing screens must never show the
        // old geometric prototype. Exact generated combinations win first;
        // otherwise use the nearest HD presentation asset until that precise
        // body / hair / sport / pose render is added to the catalog.
        if avatar.presentation == .feminine {
            if pose == .neutral,
               sport == .running,
               avatar.skinTone == .warmMedium,
               avatar.hairStyle == .tied,
               avatar.hairColor == .espresso,
               avatar.bodyPreset == .balanced {
                let loadout = avatar.loadout(for: sport)
                if loadout.bottom == .runShortBlack,
                   loadout.headwear == nil,
                   loadout.accessory == nil {
                    switch (loadout.top, loadout.footwear) {
                    case (.runTopIvory, .runShoeWhite):
                        return "AvatarFemaleBalancedRunTopIvory"
                    case (.runTopLavender, .runShoeCobalt):
                        return "AvatarFemaleBalancedRunShoeCobalt"
                    default:
                        break
                    }
                }
            }

            return "AvatarFemaleBalancedStarterRun"
        }

        return "AvatarMaleBalancedStarterRun"
    }

    static func canonicalAssetName(
        for avatar: AthleteAvatar,
        sport: Sport,
        pose: AvatarPose
    ) -> String {
        let loadout = avatar.loadout(for: sport)
        return [
            "AvatarRender",
            avatar.presentation.rawValue,
            avatar.bodyPreset.rawValue,
            avatar.skinTone.rawValue,
            avatar.hairStyle.rawValue,
            avatar.hairColor.rawValue,
            sport.rawValue,
            loadout.top.rawValue,
            loadout.bottom.rawValue,
            loadout.footwear.rawValue,
            loadout.headwear?.rawValue ?? "none",
            loadout.accessory?.rawValue ?? "none",
            pose.rawValue
        ]
        .joined(separator: "__")
    }
}


private enum AthleteRealityAsset {
    static func url(for presentation: AvatarPresentation) -> URL? {
        let name = presentation == .feminine
            ? "AtheviaAthleteFeminine"
            : "AtheviaAthleteMasculine"

        return Bundle.main.url(forResource: name, withExtension: "usdz")
    }
}

private enum AthleteRealityConfigurator {
    static func configure(
        root: Entity,
        avatar: AthleteAvatar,
        sport: Sport,
        pose: AvatarPose
    ) {
        applyVisibility(root: root, avatar: avatar, sport: sport)
        applyMaterials(root: root, avatar: avatar, sport: sport)
        applyBodyPreset(root: root, avatar: avatar)
        applyPose(root: root, pose: pose)
    }

    private static func applyVisibility(
        root: Entity,
        avatar: AthleteAvatar,
        sport: Sport
    ) {
        setPrefix("HAIR__", enabledName: hairEntityName(avatar.hairStyle), in: root)

        let allGear = descendants(of: root).filter { $0.name.hasPrefix("GEAR__") }
        for entity in allGear {
            entity.isEnabled = false
        }

        let desired = gearEntityNames(for: avatar.loadout(for: sport), sport: sport)
        let availableNames = Set(allGear.map(\.name))
        let effective = desired.allSatisfy(availableNames.contains)
            ? desired
            : starterRunningGear

        for entity in allGear where effective.contains(entity.name) {
            entity.isEnabled = true
        }
    }

    private static func setPrefix(
        _ prefix: String,
        enabledName: String,
        in root: Entity
    ) {
        for entity in descendants(of: root) where entity.name.hasPrefix(prefix) {
            entity.isEnabled = entity.name == enabledName
        }
    }

    private static func hairEntityName(_ style: AvatarHairStyle) -> String {
        "HAIR__" + style.rawValue
    }

    private static let starterRunningGear: Set<String> = [
        "GEAR__runTopPerformance",
        "GEAR__runShort",
        "GEAR__runShoe"
    ]

    private static func gearEntityNames(
        for loadout: AvatarLoadout,
        sport: Sport
    ) -> Set<String> {
        switch sport {
        case .running:
            starterRunningGear
        case .cycling:
            [
                "GEAR__cycleJersey",
                "GEAR__cycleBib",
                "GEAR__cycleShoe"
            ]
        case .swimming:
            [
                "GEAR__swimSuit"
            ]
        }
    }

    private static func applyMaterials(
        root: Entity,
        avatar: AthleteAvatar,
        sport: Sport
    ) {
        recolor(
            entityNamed: bodyEntityName(avatar.presentation),
            in: root,
            color: color(avatar.skinTone.rgb),
            roughness: 0.62
        )
        recolor(
            entityNamed: hairEntityName(avatar.hairStyle),
            in: root,
            color: color(avatar.hairColor.rgb),
            roughness: 0.48
        )

        let loadout = avatar.loadout(for: sport)
        recolor(
            entityNamed: "GEAR__runTopPerformance",
            in: root,
            color: topColor(loadout.top),
            roughness: 0.72
        )
        recolor(
            entityNamed: "GEAR__runShort",
            in: root,
            color: bottomColor(loadout.bottom),
            roughness: 0.76
        )
        recolor(
            entityNamed: "GEAR__runShoe",
            in: root,
            color: footwearColor(loadout.footwear),
            roughness: 0.60
        )
    }

    private static func bodyEntityName(_ presentation: AvatarPresentation) -> String {
        presentation == .feminine ? "BODY__feminine" : "BODY__masculine"
    }

    private static func recolor(
        entityNamed name: String,
        in root: Entity,
        color: UIColor,
        roughness: Float
    ) {
        guard let entity = root.findEntity(named: name) else { return }

        let material = SimpleMaterial(
            color: color,
            roughness: .float(roughness),
            isMetallic: false
        )

        for candidate in descendants(of: entity) {
            guard var model = candidate.components[ModelComponent.self] else {
                continue
            }

            if model.materials.isEmpty {
                model.materials = [material]
            } else {
                model.materials = model.materials.map { existing -> any Material in
                    if var pbr = existing as? PhysicallyBasedMaterial {
                        pbr.baseColor = PhysicallyBasedMaterial.BaseColor(
                            tint: color,
                            texture: pbr.baseColor.texture
                        )
                        return pbr
                    }

                    return material
                }
            }
            candidate.components.set(model)
        }
    }

    private static func applyBodyPreset(
        root: Entity,
        avatar: AthleteAvatar
    ) {
        guard let body = root.findEntity(named: bodyEntityName(avatar.presentation)),
              let modelEntity = firstModelEntity(in: body),
              let model = modelEntity.components[ModelComponent.self] else {
            return
        }

        let mapping = BlendShapeWeightsMapping(meshResource: model.mesh)
        var component = modelEntity.components[BlendShapeWeightsComponent.self]
            ?? BlendShapeWeightsComponent(weightsMapping: mapping)
        var set = component.weightSet

        guard var data = set.default else {
            modelEntity.components.set(component)
            return
        }

        var weights = data.weights
        for (index, name) in data.weightNames.enumerated() {
            let value: Float
            switch (avatar.bodyPreset, name) {
            case (.lean, let name) where name.contains("BODY__lean"):
                value = 1
            case (.powerful, let name) where name.contains("BODY__powerful"):
                value = 1
            case (_, let name) where name.contains("BODY__lean") || name.contains("BODY__powerful"):
                value = 0
            default:
                continue
            }

            let weightIndex = weights.index(weights.startIndex, offsetBy: index)
            weights[weightIndex] = value
        }

        data.weights = weights
        set.default = data
        component.weightSet = set
        modelEntity.components.set(component)
    }

    private static func applyPose(root: Entity, pose: AvatarPose) {
        guard pose != .neutral,
              let model = firstSkinnedModel(in: root) else {
            return
        }

        let rotations = poseRotations(pose)
        guard !rotations.isEmpty else { return }

        var transforms = model.jointTransforms
        for (index, fullName) in model.jointNames.enumerated() {
            let shortName = fullName.split(separator: "/").last.map(String.init) ?? fullName
            guard let degrees = rotations[shortName],
                  index < transforms.count else {
                continue
            }

            var transform = transforms[index]
            transform.rotation = quaternion(degrees: degrees)
            transforms[index] = transform
        }
        model.jointTransforms = transforms
    }

    private static func firstModelEntity(in root: Entity) -> Entity? {
        if root.components[ModelComponent.self] != nil {
            return root
        }

        for child in root.children {
            if let entity = firstModelEntity(in: child) {
                return entity
            }
        }
        return nil
    }

    private static func firstSkinnedModel(in root: Entity) -> ModelEntity? {
        if let model = root as? ModelEntity, !model.jointNames.isEmpty {
            return model
        }

        for child in root.children {
            if let model = firstSkinnedModel(in: child) {
                return model
            }
        }
        return nil
    }

    private static func poseRotations(
        _ pose: AvatarPose
    ) -> [String: SIMD3<Float>] {
        switch pose {
        case .neutral:
            [:]
        case .runReady:
            [
                "pelvis": [4, 0, 0],
                "spine_02": [-4, 0, 0],
                "upperarm_l": [12, 0, -24],
                "lowerarm_l": [-55, 0, 0],
                "upperarm_r": [-12, 0, 24],
                "lowerarm_r": [-55, 0, 0]
            ]
        case .running:
            [
                "pelvis": [8, 0, 0],
                "spine_02": [-8, 0, 0],
                "upperarm_l": [20, 0, -38],
                "lowerarm_l": [-72, 0, 0],
                "upperarm_r": [-20, 0, 38],
                "lowerarm_r": [-72, 0, 0],
                "thigh_l": [-28, 0, 0],
                "calf_l": [22, 0, 0],
                "thigh_r": [24, 0, 0],
                "calf_r": [55, 0, 0]
            ]
        case .cycling:
            [
                "pelvis": [18, 0, 0],
                "spine_01": [-10, 0, 0],
                "spine_02": [-14, 0, 0],
                "upperarm_l": [8, 0, -42],
                "lowerarm_l": [-42, 0, 0],
                "upperarm_r": [-8, 0, 42],
                "lowerarm_r": [-42, 0, 0]
            ]
        case .swimming:
            [
                "spine_02": [-6, 0, 0],
                "upperarm_l": [0, 0, -155],
                "lowerarm_l": [-18, 0, 0],
                "upperarm_r": [0, 0, 155],
                "lowerarm_r": [-18, 0, 0]
            ]
        case .recovery:
            [
                "spine_02": [3, 0, 0],
                "upperarm_l": [2, 0, -8],
                "upperarm_r": [-2, 0, 8],
                "head": [2, 0, 0]
            ]
        case .celebration:
            [
                "spine_02": [-4, 0, 0],
                "upperarm_l": [0, 0, -125],
                "lowerarm_l": [-15, 0, 0],
                "upperarm_r": [0, 0, 125],
                "lowerarm_r": [-15, 0, 0],
                "head": [-4, 0, 0]
            ]
        }
    }

    private static func quaternion(degrees: SIMD3<Float>) -> simd_quatf {
        let radians = degrees * (.pi / 180)
        let x = simd_quatf(angle: radians.x, axis: [1, 0, 0])
        let y = simd_quatf(angle: radians.y, axis: [0, 1, 0])
        let z = simd_quatf(angle: radians.z, axis: [0, 0, 1])
        return z * y * x
    }

    private static func color(
        _ rgb: (Double, Double, Double)
    ) -> UIColor {
        UIColor(
            red: CGFloat(rgb.0),
            green: CGFloat(rgb.1),
            blue: CGFloat(rgb.2),
            alpha: 1
        )
    }

    private static func topColor(_ id: AvatarGearID) -> UIColor {
        switch id {
        case .runTopLavender:
            UIColor(red: 0.47, green: 0.42, blue: 0.88, alpha: 1)
        case .runTopIvory:
            UIColor(red: 0.92, green: 0.91, blue: 0.88, alpha: 1)
        case .runTopCobalt:
            UIColor(red: 0.18, green: 0.32, blue: 0.88, alpha: 1)
        default:
            UIColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
        }
    }

    private static func bottomColor(_ id: AvatarGearID) -> UIColor {
        switch id {
        case .runShortSlate:
            UIColor(red: 0.22, green: 0.24, blue: 0.29, alpha: 1)
        default:
            UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
        }
    }

    private static func footwearColor(_ id: AvatarGearID) -> UIColor {
        switch id {
        case .runShoeCobalt:
            UIColor(red: 0.18, green: 0.32, blue: 0.88, alpha: 1)
        case .cycleShoeBlack:
            UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        default:
            .white
        }
    }

    private static func descendants(of root: Entity) -> [Entity] {
        [root] + root.children.flatMap { descendants(of: $0) }
    }
}

private struct AthleteRealityAvatarView: View {
    let avatar: AthleteAvatar
    let sport: Sport
    let pose: AvatarPose

    private var assetURL: URL? {
        AthleteRealityAsset.url(for: avatar.presentation)
    }

    var body: some View {
        Group {
            if let assetURL {
                RealityView { content in
                    content.camera = .virtual

                    guard let athlete = try? await Entity(contentsOf: assetURL) else {
                        return
                    }
                    athlete.name = "ATHEVIA__athlete"
                    AthleteRealityConfigurator.configure(
                        root: athlete,
                        avatar: avatar,
                        sport: sport,
                        pose: pose
                    )
                    content.add(athlete)

                    let camera = Entity()
                    camera.name = "ATHEVIA__camera"
                    camera.position = [0, 0.92, 2.75]
                    camera.look(
                        at: [0, 0.92, 0],
                        from: camera.position,
                        relativeTo: nil
                    )
                    camera.components.set(
                        PerspectiveCameraComponent(
                            near: 0.01,
                            far: 20,
                            fieldOfViewInDegrees: 33
                        )
                    )
                    content.add(camera)
                } update: { content in
                    guard let athlete = content.entities.first(where: {
                        $0.name == "ATHEVIA__athlete"
                    }) else {
                        return
                    }

                    AthleteRealityConfigurator.configure(
                        root: athlete,
                        avatar: avatar,
                        sport: sport,
                        pose: pose
                    )
                } placeholder: {
                    ProgressView()
                        .tint(.white)
                }
                .realityViewCameraControls(.orbit)
                .id("(avatar.presentation.rawValue)-(pose.rawValue)")
            }
        }
    }
}


struct AthleteAvatarView: View {
    let avatar: AthleteAvatar
    var sport: Sport = .running
    var pose: AvatarPose = .neutral
    var size: CGFloat = 280

    private var skin: Color {
        let rgb = avatar.skinTone.rgb
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private var hair: Color {
        let rgb = avatar.hairColor.rgb
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private var loadout: AvatarLoadout {
        avatar.loadout(for: sport)
    }

    private var sportAccent: Color {
        switch sport {
        case .running: Color(red: 0.32, green: 0.42, blue: 0.96)
        case .cycling: Color(red: 0.12, green: 0.70, blue: 0.65)
        case .swimming: Color(red: 0.12, green: 0.60, blue: 0.92)
        }
    }

    private var topColor: Color {
        switch loadout.top {
        case .runTopLavender:
            Color(red: 0.47, green: 0.42, blue: 0.88)
        case .runTopIvory:
            Color(red: 0.92, green: 0.91, blue: 0.88)
        case .runTopCobalt, .cycleJerseyCobalt, .swimSuitCobalt:
            Color(red: 0.18, green: 0.32, blue: 0.88)
        case .cycleJerseyGraphite, .runTopGraphite, .swimSuitGraphite:
            Color(red: 0.12, green: 0.13, blue: 0.16)
        default:
            sportAccent
        }
    }

    private var bottomColor: Color {
        switch loadout.bottom {
        case .runShortSlate:
            Color(red: 0.22, green: 0.24, blue: 0.29)
        default:
            Color(red: 0.07, green: 0.08, blue: 0.10)
        }
    }

    private var footwearColor: Color {
        switch loadout.footwear {
        case .runShoeCobalt:
            Color(red: 0.18, green: 0.32, blue: 0.88)
        case .cycleShoeBlack:
            Color(red: 0.06, green: 0.07, blue: 0.09)
        case .barefoot:
            skin
        default:
            Color(red: 0.94, green: 0.94, blue: 0.92)
        }
    }

    private var productionAssetName: String? {
        AvatarRenderAssetResolver.assetName(
            for: avatar,
            sport: sport,
            pose: pose
        )
    }

    var body: some View {
        Group {
            if size >= 160,
               AthleteRealityAsset.url(for: avatar.presentation) != nil {
                AthleteRealityAvatarView(
                    avatar: avatar,
                    sport: sport,
                    pose: pose
                )
                .frame(width: size * 0.90, height: size)
            } else {
                Image(productionAssetName ?? fallbackProductionAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.80, height: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Athlete avatar")
    }

    private var fallbackProductionAssetName: String {
        avatar.presentation == .feminine
            ? "AvatarFemaleBalancedStarterRun"
            : "AvatarMaleBalancedStarterRun"
    }

    private var legs: some View {
        HStack(spacing: size * 0.045) {
            Capsule()
                .fill(skin)
                .frame(width: size * 0.075, height: size * 0.31)
            Capsule()
                .fill(skin)
                .frame(width: size * 0.075, height: size * 0.31)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: size * 0.018) {
                shoe
                shoe
            }
            .offset(y: size * 0.035)
        }
        .offset(y: size * 0.25)
    }

    private var shoe: some View {
        Capsule()
            .fill(footwearColor)
            .overlay {
                Capsule()
                    .stroke(.black.opacity(0.12), lineWidth: 1)
            }
            .frame(width: size * 0.12, height: size * 0.045)
    }

    private var torso: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [topColor.opacity(0.98), topColor.opacity(0.76)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(
                    width: size * 0.32 * avatar.bodyPreset.shoulderScale,
                    height: size * 0.22
                )

            RoundedRectangle(cornerRadius: size * 0.035, style: .continuous)
                .fill(bottomColor)
                .frame(width: size * 0.30, height: size * 0.12)
                .offset(y: -size * 0.018)
        }
        .offset(y: size * 0.045)
    }

    private var arms: some View {
        HStack(spacing: size * 0.29 * avatar.bodyPreset.shoulderScale) {
            Capsule()
                .fill(skin)
                .frame(width: size * 0.055, height: size * 0.26)
                .rotationEffect(.degrees(7))
            Capsule()
                .fill(skin)
                .frame(width: size * 0.055, height: size * 0.26)
                .rotationEffect(.degrees(-7))
        }
        .offset(y: size * 0.065)
    }

    private var head: some View {
        VStack(spacing: -2) {
            Ellipse()
                .fill(skin)
                .frame(width: size * 0.17, height: size * 0.205)
                .overlay(alignment: .center) {
                    HStack(spacing: size * 0.045) {
                        Circle().fill(.black.opacity(0.72)).frame(width: 3.5, height: 3.5)
                        Circle().fill(.black.opacity(0.72)).frame(width: 3.5, height: 3.5)
                    }
                    .offset(y: -size * 0.015)
                }

            Capsule()
                .fill(skin)
                .frame(width: size * 0.065, height: size * 0.05)
        }
        .offset(y: -size * 0.225)
    }

    @ViewBuilder
    private var hairShape: some View {
        switch avatar.hairStyle {
        case .cropped, .closeCut:
            Ellipse()
                .trim(from: 0, to: 0.56)
                .fill(hair)
                .frame(width: size * 0.18, height: size * 0.16)
                .rotationEffect(.degrees(180))
                .offset(y: -size * 0.285)
        case .swept, .textured:
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(hair)
                .frame(width: size * 0.19, height: size * 0.095)
                .rotationEffect(.degrees(-7))
                .offset(y: -size * 0.31)
        case .tied:
            ZStack {
                Ellipse()
                    .fill(hair)
                    .frame(width: size * 0.18, height: size * 0.10)
                Circle()
                    .fill(hair)
                    .frame(width: size * 0.065, height: size * 0.065)
                    .offset(x: size * 0.085, y: -size * 0.02)
            }
            .offset(y: -size * 0.31)
        case .long:
            Capsule()
                .fill(hair)
                .frame(width: size * 0.20, height: size * 0.25)
                .offset(y: -size * 0.24)
                .overlay {
                    Ellipse()
                        .fill(skin)
                        .frame(width: size * 0.155, height: size * 0.19)
                        .offset(y: -size * 0.255)
                }
        }
    }
    @ViewBuilder
    private var headwearLayer: some View {
        switch loadout.headwear {
        case .runCapBlack:
            ZStack {
                Capsule()
                    .fill(Color(red: 0.06, green: 0.07, blue: 0.09))
                    .frame(width: size * 0.19, height: size * 0.07)
                Capsule()
                    .fill(Color(red: 0.06, green: 0.07, blue: 0.09))
                    .frame(width: size * 0.10, height: size * 0.025)
                    .offset(x: size * 0.075, y: size * 0.025)
            }
            .offset(y: -size * 0.32)

        case .cycleHelmetBlack, .cycleHelmetWhite:
            let helmetColor = loadout.headwear == .cycleHelmetWhite
                ? Color(red: 0.92, green: 0.93, blue: 0.94)
                : Color(red: 0.05, green: 0.06, blue: 0.08)

            ZStack {
                Ellipse()
                    .fill(helmetColor)
                    .frame(width: size * 0.20, height: size * 0.10)
                HStack(spacing: size * 0.016) {
                    Capsule().fill(.black.opacity(0.28))
                    Capsule().fill(.black.opacity(0.28))
                    Capsule().fill(.black.opacity(0.28))
                }
                .frame(width: size * 0.13, height: size * 0.018)
            }
            .offset(y: -size * 0.325)

        case .swimCapBlack, .swimCapWhite:
            Ellipse()
                .fill(
                    loadout.headwear == .swimCapWhite
                        ? Color(red: 0.93, green: 0.94, blue: 0.95)
                        : Color(red: 0.05, green: 0.06, blue: 0.08)
                )
                .frame(width: size * 0.185, height: size * 0.105)
                .offset(y: -size * 0.315)

        case .none:
            EmptyView()

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var accessoryLayer: some View {
        if loadout.accessory == .swimGogglesSmoke {
            HStack(spacing: size * 0.01) {
                Capsule()
                    .fill(Color.black.opacity(0.72))
                    .frame(width: size * 0.055, height: size * 0.025)
                Capsule()
                    .fill(Color.black.opacity(0.72))
                    .frame(width: size * 0.055, height: size * 0.025)
            }
            .overlay {
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: size * 0.02, height: size * 0.008)
            }
            .offset(y: -size * 0.255)
        }
    }
}

struct AthleteAvatarStudioView: View {
    @Environment(\.atheviaTheme) private var theme
    @Binding var avatar: AthleteAvatar
    var selectedSports: [Sport]
    var showsCompletionButton = false
    var onComplete: (() -> Void)?

    @State private var selectedSport: Sport = .running

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                sportSelector
                appearance
                starterKit

                if showsCompletionButton {
                    Button("Continue") {
                        onComplete?()
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.025, blue: 0.045),
                    Color(red: 0.025, green: 0.045, blue: 0.075)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Customize Athlete")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(red: 0.015, green: 0.025, blue: 0.045), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if let first = selectedSports.first {
                selectedSport = first
            }
        }
    }

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            theme.color(.hero, classic: Color(red: 0.08, green: 0.10, blue: 0.16)),
                            theme.color(.canvas, classic: Color(red: 0.02, green: 0.03, blue: 0.06))
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(theme.color(.accent, classic: .white).opacity(0.10))
                .frame(width: 220, height: 220)
                .blur(radius: 2)
                .offset(x: 90, y: -80)

            VStack(spacing: 10) {
                AthleteAvatarView(avatar: avatar, sport: selectedSport, size: 360)
                    .frame(height: 360)

                VStack(spacing: 4) {
                    Text("YOUR ATHLETE")
                        .font(.caption.weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.58))
                    Text(selectedSport.displayName + " look")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 18)
            }
        }
        .frame(minHeight: 440)
        .clipShape(.rect(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.20), radius: 24, y: 12)
    }

    @ViewBuilder
    private var sportSelector: some View {
        if selectedSports.count > 1 {
            Picker("Outfit", selection: $selectedSport) {
                ForEach(selectedSports, id: \.self) { sport in
                    Text(sport.displayName).tag(sport)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                "Appearance",
                detail: "Build a recognizable athlete identity. You can change this later."
            )

            controlRow("Style") {
                Picker("Style", selection: $avatar.presentation) {
                    ForEach(AvatarPresentation.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Skin tone")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    ForEach(AvatarSkinTone.allCases) { tone in
                        Button {
                            avatar.skinTone = tone
                        } label: {
                            Circle()
                                .fill(skinColor(tone))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    Circle()
                                        .stroke(
                                            avatar.skinTone == tone
                                                ? theme.color(.accent, classic: .blue)
                                                : .white.opacity(0.10),
                                            lineWidth: avatar.skinTone == tone ? 3 : 1
                                        )
                                        .padding(-3)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tone.rawValue)
                        .accessibilityAddTraits(avatar.skinTone == tone ? .isSelected : [])
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Hair")
                    .font(.subheadline.weight(.semibold))
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(AvatarHairStyle.allCases) { style in
                        premiumChoice(
                            title: style.displayName,
                            selected: avatar.hairStyle == style
                        ) {
                            avatar.hairStyle = style
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Build")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 10) {
                    ForEach(AvatarBodyPreset.allCases) { preset in
                        premiumChoice(
                            title: preset.displayName,
                            selected: avatar.bodyPreset == preset
                        ) {
                            avatar.bodyPreset = preset
                        }
                    }
                }
            }
        }
    }

    private var starterKit: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                "Starter kit",
                detail: "Training unlocks additional gear. Cosmetic choices never affect your plan."
            )

            HStack(spacing: 12) {
                gearCard(icon: "tshirt.fill", title: "Performance top")
                gearCard(icon: "shoe.fill", title: "Training shoes")
                gearCard(icon: selectedSport == .cycling ? "bicycle.helmet" : "sparkles", title: "Sport kit")
            }
        }
    }

    private func controlRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            content()
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private func premiumChoice(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .white : .white.opacity(0.70))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    selected
                        ? theme.color(.accent, classic: .blue)
                        : Color.white.opacity(0.07),
                    in: .rect(cornerRadius: 13)
                )
        }
        .buttonStyle(.plain)
    }

    private func gearCard(icon: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .frame(height: 28)
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .padding(10)
        .background(
            theme.color(.raisedSurface, classic: Color(uiColor: .secondarySystemBackground)),
            in: .rect(cornerRadius: 18)
        )
    }

    private func skinColor(_ tone: AvatarSkinTone) -> Color {
        let rgb = tone.rgb
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

struct AthleteAvatarOnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        AthleteAvatarStudioView(
            avatar: Binding(
                get: { model.avatar },
                set: { model.choose(avatar: $0) }
            ),
            selectedSports: model.selectedSports.isEmpty ? [.running] : model.selectedSports,
            showsCompletionButton: true,
            onComplete: model.advance
        )
        .navigationTitle("Create your athlete")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Athlete Studio") {
    NavigationStack {
        AthleteAvatarStudioView(
            avatar: .constant(.starter),
            selectedSports: [.running, .cycling, .swimming]
        )
    }
}
#endif
