<template>
  <div
    class="relative flex min-h-screen items-center justify-center overflow-hidden bg-slate-100 p-4 dark:bg-[#0b1220]"
  >
    <!-- Soft atmosphere (not flat) -->
    <div
      class="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_top,_rgba(59,130,246,0.18),_transparent_55%),radial-gradient(ellipse_at_bottom_right,_rgba(14,165,233,0.12),_transparent_45%)] dark:bg-[radial-gradient(ellipse_at_top,_rgba(59,130,246,0.22),_transparent_50%),radial-gradient(ellipse_at_bottom_right,_rgba(30,64,175,0.25),_transparent_40%)]"
    />
    <div
      class="pointer-events-none absolute -left-24 top-24 h-72 w-72 rounded-full bg-blue-400/20 blur-3xl dark:bg-blue-500/10"
    />
    <div
      class="pointer-events-none absolute -right-16 bottom-10 h-80 w-80 rounded-full bg-cyan-300/20 blur-3xl dark:bg-sky-600/10"
    />

    <div class="relative w-full max-w-lg">
      <slot />
    </div>
  </div>
</template>
