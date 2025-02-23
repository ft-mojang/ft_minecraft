const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe_name = "ft_minecraft";
    const root_source_file = b.path("src/main.zig");
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_validation_layers = b.option(
        bool,
        "validation_layers",
        "Enable validation layers (default: true iff debug)",
    ) orelse (optimize == .Debug);

    const options = b.addOptions();
    options.addOption(bool, "validation_layers", enable_validation_layers);

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });

    const check = b.addExecutable(.{
        .name = exe_name,
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });

    const exe_unit_tests = b.addTest(.{
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });

    const executables = [_]*std.Build.Step.Compile{exe, check, exe_unit_tests};

    const vertex_shader_module = b.addModule("shader.vert", .{
        .root_source_file = compileShader(
            b,
            b.path("shaders/shader.vert"),
            "shader.vert.spv",
        ),
    });

    const fragment_shader_module = b.addModule("shader.frag", .{
        .root_source_file = compileShader(
            b,
            b.path("shaders/shader.frag"),
            "shader.frag.spv",
        ),
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    const zm = b.dependency("zm", .{
        .target = target,
        .optimize = optimize,
    }).module("zm");

    const mach_glfw = b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    }).module("mach-glfw");

    // Get the (lazy) path to vk.xml:
    const registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");
    // Get generator executable reference
    const vk_gen = b.dependency("vulkan_zig", .{}).artifact("vulkan-zig-generator");
    // Set up a run step to generate the bindings
    const vk_generate_cmd = b.addRunArtifact(vk_gen);
    // Pass the registry to the generator
    vk_generate_cmd.addFileArg(registry);
    // Add the generator's output as a module
    const vk_module = b.createModule(.{
        .root_source_file = vk_generate_cmd.addOutputFileArg("vk.zig"),
    });

    for (executables) |executable| {
        // Add options as a moduble importable with @import("config")
        executable.root_module.addOptions("config", options);

        executable.root_module.addImport("zm", zm);
        executable.root_module.addImport("mach-glfw", mach_glfw);
        executable.root_module.addImport("vulkan", vk_module);
        executable.root_module.addImport("shader.vert", vertex_shader_module);
        executable.root_module.addImport("shader.frag", fragment_shader_module);
    }

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const check_step = b.step("check", "Check build");
    check_step.dependOn(&check.step);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn compileShader(
    b: *std.Build,
    input_path: std.Build.LazyPath,
    output_name: []const u8,
) std.Build.LazyPath {
    const command = b.addSystemCommand(&.{"glslangValidator"});
    command.addArgs(&.{"--target-env", "vulkan1.2"});
    command.addArg("-o");
    const output = command.addOutputFileArg(output_name);
    command.addFileArg(input_path);
    return output;
}

