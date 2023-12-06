const plugin = require('tailwindcss/plugin')

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
      }
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
        current: 'currentColor',
      }
    }
  },
  plugins: [
    require("@tailwindcss/typography"),
    require("daisyui"),
    plugin(({ addVariant }) => addVariant('phx-no-feedback', ['.phx-no-feedback&', '.phx-no-feedback &'])),
    plugin(({ addVariant }) => addVariant('phx-click-loading', ['.phx-click-loading&', '.phx-click-loading &'])),
    plugin(({ addVariant }) => addVariant('phx-submit-loading', ['.phx-submit-loading&', '.phx-submit-loading &'])),
    plugin(({ addVariant }) => addVariant('phx-change-loading', ['.phx-change-loading&', '.phx-change-loading &']))
  ]
}
