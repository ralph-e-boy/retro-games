import UIKit
import Metal2D
internal import MetalKit

class AsteroidsViewController: UIViewController {

    private var processingView: ProcessingKitView!
    private var touchOverlay: TouchOverlayView!
    private var panel: AsteroidsDemoPanel!
    private var backButton: UIButton!
    var onDismiss: (() -> Void)?

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Asteroids"
        view.backgroundColor = .black

        panel = AsteroidsDemoPanel()

        setupProcessingView()
        setupTouchOverlay()
        setupBackButton()
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let scale = processingView.contentScaleFactor
        let panelBounds = CGRect(
            x: 0, y: 0,
            width: processingView.bounds.width * scale,
            height: processingView.bounds.height * scale
        )
        panel.bounds = panelBounds
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
}
