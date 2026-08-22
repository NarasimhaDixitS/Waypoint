import Foundation
import Supabase

enum SupabaseManager {
    /// Project URL + publishable (anon) key from Settings -> API. Safe to embed client-side --
    /// every table's RLS policy is what actually restricts access, not this key.
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://wmufgewwglmuhiabbhfz.supabase.co")!,
        supabaseKey: "sb_publishable_KOnQ4Hkt9_PcjAvROzshGw_wsC2Wxm1"
    )
}
