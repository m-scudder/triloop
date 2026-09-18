import Foundation
import Supabase

enum SupabaseConfiguration {
    static let projectRef = "njrbzobygmewfdfwcvqc"
    static let url = URL(string: "https://njrbzobygmewfdfwcvqc.supabase.co")!
    static let publishableKey = "sb_publishable_nYbFcvkWKM7gL9JLCDLELw_dOsuuF-0"

    static let client: SupabaseClient = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: publishableKey,
            options: SupabaseClientOptions(
                db: .init(encoder: encoder, decoder: decoder)
            )
        )
    }()
}
