# Keep the desktop responsive while the CPU is saturated (builds, installs, games).
{
  # sched_ext scheduler that recognises interactive tasks (compositor, input,
  # focused apps) by behaviour and runs them ahead of CPU-bound work.
  services.scx-loader = {
    enable = true;
    config.default_sched = "scx_bpfland";
  };

  # Package builds and downloads only get CPU and disk time nobody else wants.
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";
  # 28 threads: at most 4 jobs x 7 cores, never more than the machine has.
  nix.settings = {
    max-jobs = 4;
    cores = 7;
  };

  # The logged-in session outweighs system services and keeps a memory floor.
  systemd.slices."user-1000" = {
    overrideStrategy = "asDropin";
    sliceConfig = {
      CPUWeight = 500;
      MemoryLow = "2G";
    };
  };
}
