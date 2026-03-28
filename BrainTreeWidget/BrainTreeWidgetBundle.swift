//
//  BrainTreeWidgetBundle.swift
//  BrainTreeWidget
//
//  Created by rodney on 3/27/26.
//

import WidgetKit
import SwiftUI

@main
struct BrainTreeWidgetBundle: WidgetBundle {
    var body: some Widget {
        BrainTreeWidget()
        BrainTreeWidgetControl()
        BrainTreeWidgetLiveActivity()
    }
}
