const plugin = require('tailwindcss/plugin')
const fs = require('fs')
const path = require('path')

module.exports = {
  daisyui: {
    themes: [
      {
        light: {
          ...require('daisyui/src/theming/themes').light,
          primary: '#1d4ed8',
          'primary-content': 'white',
          secondary: '#f39325',
          'secondary-content': 'white'
        }
      },
      'dark',
      'cupcake',
      'bumblebee',
      'emerald',
      'corporate',
      'synthwave',
      'retro',
      'cyberpunk',
      'valentine',
      'halloween',
      'garden',
      'forest',
      'aqua',
      'lofi',
      'pastel',
      'fantasy',
      'wireframe',
      'black',
      'luxury',
      'dracula',
      'cmyk',
      'autumn',
      'business',
      'acid',
      'lemonade',
      'night',
      'coffee',
      'winter',
      'dim',
      'nord',
      'sunset'
    ]
  },
  content: [
    'assets/js/**/*.js',
    'lib/*_web.ex',
    'lib/*_web/**/*.{ex,heex}',
    '../lib/**/*.*ex'
  ],
  safelist: [
    'input'
  ],
  theme: {
    container: {
      center: true,
      padding: '2rem'
    },
    extend: {
      colors: {
        transparent: 'transparent',
        current: 'currentColor'
      }
    }
  },
  plugins: [
    require('@tailwindcss/typography'),
    require('daisyui'),
    plugin(({ addVariant }) => addVariant('phx-click-loading', ['.phx-click-loading&', '.phx-click-loading &'])),
    plugin(({ addVariant }) => addVariant('phx-submit-loading', ['.phx-submit-loading&', '.phx-submit-loading &'])),
    plugin(({ addVariant }) => addVariant('phx-change-loading', ['.phx-change-loading&', '.phx-change-loading &'])),
    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function ({ matchComponents, theme }) {
      const iconsDir = path.join(__dirname, '../deps/heroicons/optimized')
      const values = {}
      const icons = [
        ['', '/24/outline'],
        ['-solid', '/24/solid'],
        ['-mini', '/20/solid'],
        ['-micro', '/16/solid']
      ]
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
          const name = path.basename(file, '.svg') + suffix
          values[name] = { name, fullPath: path.join(iconsDir, dir, file) }
        })
      })
      matchComponents({
        hero: ({ name, fullPath }) => {
          const content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, '')
          let size = theme('spacing.6')
          if (name.endsWith('-mini')) {
            size = theme('spacing.5')
          } else if (name.endsWith('-micro')) {
            size = theme('spacing.4')
          }
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            '-webkit-mask': `var(--hero-${name})`,
            mask: `var(--hero-${name})`,
            'mask-repeat': 'no-repeat',
            'background-color': 'currentColor',
            'vertical-align': 'middle',
            display: 'inline-block',
            width: size,
            height: size
          }
        }
      }, { values })
    })
  ]
}
