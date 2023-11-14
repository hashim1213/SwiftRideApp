# SwiftRideApp

**Overview**

Swift Ride is an iOS application designed to provide real-time information about bus stops. It features an interactive map, a list of nearby bus stops, and a favorites section for easy access to frequently used stops. It uses Winnipeg Bus Tranist Open Data API. 

**Features**
- Interactive Map: View bus stops on a map, with real-time updates and detailed information for each stop.
- Nearby Bus Stops: Discover bus stops closest to your current location.
- Favorites: Save your most-used bus stops for quick and easy access.
- Custom UI Elements: Includes a custom tab bar with rounded corners for a sleek, modern look.
- Location Services: Utilize the device's location to find nearby bus stops and display current location details.


**Technical Details**

- Built with SwiftUI.
- Uses a singleton pattern for managing bus stop data (BusStopProvider).
- Implements custom UI modifications for the tab bar appearance.
- Implements floating action buttons for refreshing data and accessing location information.
- Fetches and displays bus stop data upon app launch and via user interactions.
  
**How to Use**

1. Launch the App: Open Swift Ride on your iOS device.
2. Explore the Map: Browse bus stops on the map or use the 'Nearby' tab to find stops close to you.
3. Add Favorites: Use the 'Favorites' tab to keep track of your most-used bus stops.
4. Refresh Data: Tap the refresh button to update bus stop information.
5. View Location: Use the location button to view your current location.

**Dependencies**
iOS 13.0 or later.
SwiftUI framework.
**Setup**
Clone the repository, open the project in Xcode, and run it on a simulator or a real device.
