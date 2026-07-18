import esbuild from 'esbuild'
import path from 'node:path'

const options = {
  entryPoints: ['app/assets/javascripts/boot.js'],
  bundle: true,
  format: 'esm',
  sourcemap: true,
  outdir: 'app/assets/builds',
  publicPath: '/assets',
  absWorkingDir: process.cwd(),
  tsconfig: 'jsconfig.json',
}

if (process.argv.includes('--watch')) {
  const ctx = await esbuild.context(options)
  await ctx.watch()
  console.log('esbuild watching: app/assets/javascripts/boot.js → app/assets/builds')
} else {
  await esbuild.build(options)
}
