//
//  MainView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: MainViewModel

    @State var selectedLandmark: Landmark? = nil

    var body: some View {

        return ZStack {
            MapView(
                landmarks: $viewModel.landmarks,
                selectedLandmark: $selectedLandmark
            ).edgesIgnoringSafeArea(.vertical)

            VStack {
                Text(String(viewModel.count))

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

                IndexSelector()
            }
            .padding(.vertical, 10)
        }
        .onAppear(perform: getData)
    }

    private func getData() {
        self.viewModel.getData()
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView(viewModel: .init())
    }
}
