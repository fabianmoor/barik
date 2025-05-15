// In Barik/Widgets/Custom/CustomFileTextWidget.swift (or similar path)
import SwiftUI

struct CustomFileTextWidget: View {
    @ObservedObject var configManager = ConfigManager.shared // Access the shared manager

    var body: some View {
        if (configManager.customFileContent == "default") {
            Text(configManager.customFileContent)
                .font(.headline) // Consistent styling
                .fontWeight(.semibold)
                .foregroundColor(.foregroundOutside) // Use Barik's colors
                .shadow(color: .foregroundShadowOutside, radius: 3) // Use Barik's shadows
                .padding(.horizontal, 5) // Give it some space
                .experimentalConfiguration(cornerRadius: 15) // Use Barik's experimental config
                .frame(maxHeight: .infinity)
                .background(Color.black.opacity(0.001)) // For tap gestures
                .monospacedDigit()
                // You can add .onTapGesture if you want it to do something
        } else {
            Text(configManager.customFileContent)
                .font(.headline) // Consistent styling
                .fontWeight(.semibold)
                .foregroundColor(.red) // Use Barik's colors
                .shadow(color: .foregroundShadowOutside, radius: 3) // Use Barik's shadows
                .padding(.horizontal, 5) // Give it some space
                .experimentalConfiguration(cornerRadius: 15) // Use Barik's experimental config
                .frame(maxHeight: .infinity)
                .background(Color.black.opacity(0.001)) // For tap gestures
                .monospacedDigit()
                // You can add .onTapGesture if you want it to do something
        }
    }
}

struct CustomFileTextWidget_Previews: PreviewProvider {
    static var previews: some View {
        // Mock ConfigManager for preview if needed, or just show basic text
        CustomFileTextWidget()
            .environmentObject(ConfigManager.shared) // For preview
            .padding()
            .background(Color.gray)
    }
}
