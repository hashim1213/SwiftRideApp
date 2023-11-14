//map view for nearby and favourites tabs 
import Foundation
import SwiftUI
import MapKit

struct StaticMapView: UIViewRepresentable {
    var coordinate: CLLocationCoordinate2D

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        let span = MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        let region = MKCoordinateRegion(center: coordinate, span: span)
        uiView.setRegion(region, animated: true)
        
        // Remove all existing annotations
        uiView.removeAnnotations(uiView.annotations)
        
        // Create a new annotation
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        uiView.addAnnotation(annotation)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: StaticMapView
        
        init(_ parent: StaticMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            mapView.isUserInteractionEnabled = false
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let identifier = "busAnnotation"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if annotationView == nil {
                // Create a new annotation view
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
            } else {
                // Reuse an old annotation view
                annotationView?.annotation = annotation
            }
            
            // Create a UIImage with the system symbol "mappin" and customize it
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold, scale: .large) // Adjust pointSize as needed
            let pinImage = UIImage(systemName: "bus.fill", withConfiguration: symbolConfig)?.withTintColor(.gray, renderingMode: .alwaysOriginal)
            
            // Create a new UIImage with the background color and corner radius
            let size = CGSize(width: 40, height: 30) // Set the desired size
            UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
            let context = UIGraphicsGetCurrentContext()!
            
            // Draw the background
            context.setFillColor(UIColor.black.withAlphaComponent(0.8).cgColor)
            let rect = CGRect(origin: .zero, size: size)
            context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 10).cgPath)
            context.fillPath()
            
            // Draw the pin image in the center
            pinImage?.draw(in: CGRect(x: (size.width - pinImage!.size.width) / 2, y: (size.height - pinImage!.size.height) / 2, width: pinImage!.size.width, height: pinImage!.size.height))
            
            let customImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            // Set the custom image as the annotation view's image
            annotationView?.image = customImage
            
            return annotationView
        }
    }
}
