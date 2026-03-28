//
//  BrainTreeWidgetLiveActivity.swift
//  BrainTreeWidget
//
//  Created by rodney on 3/27/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct BrainTreeWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct BrainTreeWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BrainTreeWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension BrainTreeWidgetAttributes {
    fileprivate static var preview: BrainTreeWidgetAttributes {
        BrainTreeWidgetAttributes(name: "World")
    }
}

extension BrainTreeWidgetAttributes.ContentState {
    fileprivate static var smiley: BrainTreeWidgetAttributes.ContentState {
        BrainTreeWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: BrainTreeWidgetAttributes.ContentState {
         BrainTreeWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: BrainTreeWidgetAttributes.preview) {
   BrainTreeWidgetLiveActivity()
} contentStates: {
    BrainTreeWidgetAttributes.ContentState.smiley
    BrainTreeWidgetAttributes.ContentState.starEyes
}
