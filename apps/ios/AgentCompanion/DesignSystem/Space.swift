import SwiftUI

/// 8pt grid spacing system.
/// All layout spacing must use these tokens — never hardcode point values.
enum Space {
    /// 4pt — tight internal padding
    static let xs: CGFloat = 4
    /// 8pt — standard small gap
    static let sm: CGFloat = 8
    /// 12pt — medium gap
    static let md: CGFloat = 12
    /// 16pt — standard content padding
    static let lg: CGFloat = 16
    /// 24pt — section spacing
    static let xl: CGFloat = 24
    /// 32pt — large section dividers
    static let xxl: CGFloat = 32
}
