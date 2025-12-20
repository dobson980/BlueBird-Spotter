//
//  ContentView.swift
//  BlueBird Spotter
//
//  Created by Tom Dobson on 12/19/25.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = CelesTrakViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)

            Group {
                switch viewModel.state {
                case .idle:
                    Text("No TLEs loaded.")
                case .loading:
                    ProgressView("Loading TLEs...")
                case .loaded(let tles):
                    List(tles, id: \.line1) { tle in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tle.name ?? "Unnamed satellite")
                                .font(.headline)
                            Text(tle.line1)
                                .font(.caption)
                                .monospaced()
                            Text(tle.line2)
                                .font(.caption)
                                .monospaced()
                        }
                    }
                case .error(let message):
                    Text(message)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .task {
            await viewModel.fetchTLEs(nameQuery: "SPACEMOBILE")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
