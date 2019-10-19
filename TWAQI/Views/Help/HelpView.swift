//
//  HelpView.swift
//  TWAQI
//
//  Created by kf on 28/9/19.
//  Copyright © 2019 kf. All rights reserved.
//

import SwiftUI

struct HelpView: View {
    @State var linkPage: Constants.LinkPages?

    var body: some View {
        NavigationView {
            List {
                ForEach(Constants.LinkPages.allCases) { linkPage in
                    Button(action: {
                        // setting a new value to self.linkPage
                        // this is used for triggering the SafariView presentation through .sheet()
                        self.linkPage = linkPage
                    }) {
                        Text(linkPage.title)
                            .fontWeight(.light)
                            .padding(.vertical, 12)
                    }
                }

                HStack {
                    Text("Particulates")
                        .fontWeight(.light)
                    Spacer()
                    Text("2")
                }
                .padding(.vertical, 12)
            }
            .sheet(item: $linkPage, content: { linkPage in
                SafariView(url: linkPage.url)
            })
            .navigationBarTitle("Help")
        }
    }
}

struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        HelpView()
    }
}
