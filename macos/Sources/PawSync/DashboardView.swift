import SwiftUI

struct DashboardView:View {
    @ObservedObject var model:AppModel
    @ObservedObject var catalog:PetCatalogService
    @ObservedObject var input:InputSupervisor
    @ObservedObject var focus:FocusTimer
    @ObservedObject var reminders:ReminderService
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            GroupBox("Your desk buddy") {
                VStack(alignment:.leading,spacing:12) {
                    Text(model.petName(model.preferences.companion)).font(.title2.bold())
                    Text("\(PetStore.rigIDs.count + catalog.installed.count) local companions · \(model.wardrobe.ownedHats.count) free hats").foregroundStyle(.secondary)
                    HStack { Button("Pet gallery") { model.settingsSection = .gallery }; Button("Say hello") { model.sayHello(manual:true) }; Button("Jump") { model.overlay.jumpNow() } }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(10)
            }
            GroupBox("Today’s rhythm") {
                VStack(alignment:.leading,spacing:10) {
                    Text("Focus: \(focus.phase.rawValue)\(focus.phase == .ready ? "" : " · " + focus.display)")
                    Text("\(reminders.plan.reminders.filter(\.enabled).count) enabled reminders")
                    HStack { Button("Reminders") { model.settingsSection = .reminders }; Button("Focus & habits") { model.settingsSection = .focus }; Button("Activity") { model.settingsSection = .activity } }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(10)
            }
            GroupBox("Connection health") {
                VStack(alignment:.leading,spacing:10) {
                    Label(input.running ? "Global input is active" : "Global input needs permission",systemImage:input.running ? "checkmark.circle" : "info.circle")
                    Text(input.status).font(.caption).foregroundStyle(.secondary)
                    Label(catalog.enabled ? "Gallery networking enabled" : "Gallery networking off",systemImage:"square.grid.2x2")
                    Label(model.preferences.integrations ? "Authenticated local build hooks enabled" : "Local build hooks off",systemImage:"terminal")
                    Button("Check for updates…") { model.updates.check() }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(10)
            }
        }
    }
}
