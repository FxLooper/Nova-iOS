//
//  NovaWidgetsBundle.swift
//  NovaWidgets
//
//  Created by Ondrej Belohoubek on 11.04.2026.
//  Copyright © 2026 FxLooper. All rights reserved.
//

import WidgetKit
import SwiftUI

@main
@available(iOS 16.2, *)
struct NovaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NovaLiveActivityWidget()
    }
}
