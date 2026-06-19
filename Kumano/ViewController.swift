//
//  ViewController.swift
//  Kumano
//
//  Created by au on 2026/6/19.
//

import UIKit
import SnapKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let helloLabel = UILabel()
        helloLabel.text = "Hello World"
        helloLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        helloLabel.textColor = .label

        view.addSubview(helloLabel)
        helloLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
}
