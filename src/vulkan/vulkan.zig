//! Vulkan namespace.
//!

// Re-export (flatten) subnamespaces/types
pub const Context = @import("Context.zig");

// This would make it possible to also have neatly namespaced utility functions, that don't make sense to put elsewhere.
// This also allows for not using redundant names inside the namespace context a.e. vulkanUtilityFunction here (see: main.zig)
pub fn utilityFunction() void {

}

// Namespaces should not contain mutable state! A.e. no `var x = ...`
