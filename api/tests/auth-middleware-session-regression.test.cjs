const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('auth middleware session expiry regression sweep', () => {
  const authMiddleware = read('src/middleware/auth.ts');

  test('revoked redis sessions are classified as auth failures instead of internal server errors', () => {
    expect(authMiddleware).toContain('class AuthenticationFailureError extends Error');
    expect(authMiddleware).toContain("throw new AuthenticationFailureError('Session expired or revoked')");
    expect(authMiddleware).toContain("errorResponse(res, StatusCodes.UNAUTHORIZED, err.message);");
  });
});
