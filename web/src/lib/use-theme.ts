// Thin re-export so components that only need the hook don't pull in the
// ThemeProvider JSX and trigger the react-refresh "components-only" rule.
export { useTheme } from 'next-themes';
