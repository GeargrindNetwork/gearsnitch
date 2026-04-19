import SwiftUI
import WidgetKit

// Widget bundle entry point for the watchOS complication extension. Registers
// all GearSnitch Watch complications (currently just HR).

@main
struct GearSnitchWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GearSnitchHRComplication()
    }
}
