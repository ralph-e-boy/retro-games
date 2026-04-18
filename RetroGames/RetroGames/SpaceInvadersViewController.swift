import UIKit
import Metal2D
internal import MetalKit

class SpaceInvadersViewController: UIViewController {
    private var processingView: ProcessingKitView!
    private var touchOverlay: TouchOverlayView!
    private var panel: SpaceInvadersPanel!
    private var backButton: UIButton!
    var onDismiss: (() -> Void)?

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var shouldAutorotate: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        panel = SpaceInvadersPanel()

        setupProcessingView()
        setupCRTEffect()
        setupTouchOverlay()
        setupBackButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let scale = processingView.contentScaleFactor
        panel.bounds = CGRect(
            x: 0, y: 0,
            width: processingView.bounds.width * scale,
            height: processingView.bounds.height * scale
        )
        panel.safeAreaTopInset = Float(view.safeAreaInsets.top * scale)
        panel.safeAreaBottomInset = Float(view.safeAreaInsets.bottom * scale)
    }

    private func setupProcessingView() {
        processingView = ProcessingKitView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        processingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(processingView)

        NSLayoutConstraint.activate([
            processingView.topAnchor.constraint(equalTo: view.topAnchor),
            processingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            processingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            processingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        processingView.addPanel(panel)
    }

    private func setupCRTEffect() {
        let crtShader = """
            fragment float4 fragment_crt(
                PostProcessVertexOut in [[stage_in]],
                texture2d<float> sceneTexture [[texture(0)]],
                sampler smp [[sampler(0)]],
                constant PostProcessUniforms& uniforms [[buffer(0)]]
            ) {
                float2 uv = in.texCoord;
                float2 res = uniforms.resolution;

                // Very subtle barrel distortion
                float2 centered = uv * 2.0 - 1.0;
                float r2 = dot(centered, centered);
                float distort = 1.0 + r2 * 0.03;
                float2 distUV = centered * distort * 0.5 + 0.5;

                if (distUV.x < 0.0 || distUV.x > 1.0 || distUV.y < 0.0 || distUV.y > 1.0) {
                    return float4(0, 0, 0, 1);
                }

                // Phosphor bloom: sample nearby rows to bleed brightness wider
                float py = 4.0 / res.y;
                float px = 3.0 / res.x;
                float4 color = sceneTexture.sample(smp, distUV) * 0.5;
                color += sceneTexture.sample(smp, distUV + float2(0, py)) * 0.15;
                color += sceneTexture.sample(smp, distUV - float2(0, py)) * 0.15;
                color += sceneTexture.sample(smp, distUV + float2(px, 0)) * 0.1;
                color += sceneTexture.sample(smp, distUV - float2(px, 0)) * 0.1;

                // Scanline structure — wider bands to avoid moire on retina
                float scanY = distUV.y * res.y / 3.0;
                float scanWave = sin(scanY * 3.14159 / 2.0);
                float isGap = smoothstep(0.0, 0.5, -scanWave);

                // In the gaps: dim the image and add phosphor glow
                float3 phosphor = float3(0.03, 0.08, 0.03);
                color.rgb = mix(color.rgb, color.rgb * 0.55 + phosphor, isGap);

                // Lit scanlines get a brightness boost
                float isLit = smoothstep(0.0, 0.5, scanWave);
                color.rgb += color.rgb * isLit * 0.25;

                // RGB chromatic aberration
                float offset = 0.0012;
                float cr = sceneTexture.sample(smp, distUV + float2(offset, 0)).r;
                float cb = sceneTexture.sample(smp, distUV - float2(offset, 0)).b;
                color.r = mix(color.r, cr, 0.5);
                color.b = mix(color.b, cb, 0.5);

                // Overall phosphor wash — CRT never fully black
                color.rgb += float3(0.012, 0.025, 0.012);

                // Vignette
                float vignette = 1.0 - r2 * 0.3;
                color.rgb *= vignette;

                color.rgb = min(color.rgb, float3(1.0));

                return color;
            }
        """

        guard let renderer = processingView.renderer else { return }
        do {
            try renderer.registerPostProcessEffect(
                id: "crt",
                fragmentSource: crtShader,
                fragmentFunctionName: "fragment_crt"
            )
            renderer.setPostProcessChain(["crt"])
        } catch {
            print("CRT shader error: \(error)")
        }
    }

    private func setupTouchOverlay() {
        touchOverlay = TouchOverlayView(frame: .zero)
        touchOverlay.translatesAutoresizingMaskIntoConstraints = false
        touchOverlay.backgroundColor = .clear
        touchOverlay.isMultipleTouchEnabled = true
        touchOverlay.scaleProvider = { [weak self] in
            guard let pv = self?.processingView else { return 1 }
            return pv.drawableSize.width / max(pv.bounds.width, 1)
        }
        view.addSubview(touchOverlay)

        NSLayoutConstraint.activate([
            touchOverlay.topAnchor.constraint(equalTo: processingView.topAnchor),
            touchOverlay.leadingAnchor.constraint(equalTo: processingView.leadingAnchor),
            touchOverlay.trailingAnchor.constraint(equalTo: processingView.trailingAnchor),
            touchOverlay.bottomAnchor.constraint(equalTo: processingView.bottomAnchor),
        ])

        touchOverlay.onTouchBegan = { [weak self] id, point in
            self?.panel.handleTouchBegan(id: id, at: point)
        }
        touchOverlay.onTouchMoved = { [weak self] id, point in
            self?.panel.handleTouchMoved(id: id, at: point)
        }
        touchOverlay.onTouchEnded = { [weak self] id, point in
            self?.panel.handleTouchEnded(id: id, at: point)
        }
    }

    private func setupBackButton() {
        backButton = UIButton(type: .system)
        backButton.setTitle("< BACK", for: .normal)
        backButton.setTitleColor(.gray, for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        view.addSubview(backButton)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
        ])
    }

    @objc private func backTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
        }
    }
}
