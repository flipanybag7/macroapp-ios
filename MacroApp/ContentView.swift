import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordView()
                .tabItem {
                    Label("Record", systemImage: "record.circle")
                }
                .tag(0)

            MacroListView()
                .tabItem {
                    Label("Macros", systemImage: "list.bullet.rectangle")
                }
                .tag(1)

            LuaEditorView()
                .tabItem {
                    Label("Lua", systemImage: "chevron.left.slash.chevron.right")
                }
                .tag(2)
        }
        .accentColor(.green)
    }
}
