/* Régénère index.html (version déployable PWA) à partir de prototype.html.
 *
 * prototype.html est la SOURCE DE VÉRITÉ. index.html en est une copie avec :
 *   1. le logo pointant vers le fichier local (assets/vbo-logo.png) au lieu du blob d'aperçu ;
 *   2. un bloc <head> PWA (doctype, viewport, manifest, theme-color, icônes Apple) ;
 *   3. l'enregistrement du service worker (sw.js) en fin de page.
 *
 * Usage :  node scripts/build-index.mjs
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(root, 'prototype.html');
const OUT = join(root, 'index.html');

const HEAD = `<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="description" content="Gestion des tournois du Volley-Ball Ollioulais — des poules au classement final, depuis le gymnase.">
<link rel="manifest" href="manifest.webmanifest">
<meta name="theme-color" media="(prefers-color-scheme: light)" content="#2e8b57">
<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#0f1b12">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Tournoi VBO">
<link rel="apple-touch-icon" href="icons/apple-touch-icon.png">
<link rel="icon" type="image/png" sizes="512x512" href="icons/icon-512.png">`;

const SW_REG = `
<script>
if ("serviceWorker" in navigator) {
  window.addEventListener("load", function () {
    navigator.serviceWorker.register("sw.js", { scope: "./" }).catch(function () {});
  });
}
</script>`;

let html = readFileSync(SRC, 'utf8');

// 1. Logo : blob d'aperçu -> fichier local déployable.
const before = html;
html = html.replace(/const VBO_LOGO = "[^"]*";/, 'const VBO_LOGO = "assets/vbo-logo.png";');
if (html === before) throw new Error('VBO_LOGO introuvable dans prototype.html — build interrompu.');

// 2. Bloc <head> PWA avant le <title>.
if (!/^\s*<title>/.test(html)) throw new Error('prototype.html doit commencer par <title> — build interrompu.');
html = `${HEAD}\n${html}`;

// 3. Enregistrement du service worker en fin de page.
html = html.replace(/\s*$/, '') + `\n${SW_REG}\n`;

writeFileSync(OUT, html);
console.log(`index.html régénéré (${Buffer.byteLength(html, 'utf8')} octets).`);
