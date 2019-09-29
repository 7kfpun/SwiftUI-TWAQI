//
//  MainView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI
import MapKit

struct MapView: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView {
        MKMapView(frame: .zero)
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {

    }
}

struct MainView: View {
    var body: some View {
        ZStack{
            MapView().edgesIgnoringSafeArea(.vertical)

            HStack {
                VStack {
                    Spacer()
                    button(for: "wind")
                }

                Spacer()

                VStack {
                    Spacer()

                    button(for: "square.and.arrow.up.fill")
                    button(for: "viewfinder")
                    button(for: "paperplane.fill")
                }
            }
            .padding()
            .padding(.vertical, 20)
        }
    }
}

struct MapView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
