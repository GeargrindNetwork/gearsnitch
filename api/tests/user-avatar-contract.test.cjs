const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('profile avatar contract regression sweep', () => {
  const userRoutes = read('src/modules/users/routes.ts');

  test('user routes expose a dedicated avatar update endpoint with nullable removal support', () => {
    expect(userRoutes).toContain('const updateAvatarSchema = z.object({');
    expect(userRoutes).toContain('avatarURL: avatarValueSchema.nullable()');
    expect(userRoutes).toContain("'/me/avatar'");
    expect(userRoutes).toContain('user.photoUrl = body.avatarURL ?? undefined;');
    expect(userRoutes).toContain("'Failed to update profile photo'");
  });

  test('avatar validation accepts large hosted URLs and supported data URLs only', () => {
    expect(userRoutes).toContain('const MAX_AVATAR_URL_LENGTH = 2_000_000;');
    expect(userRoutes).toContain("value.startsWith('https://')");
    expect(userRoutes).toContain("value.startsWith('http://')");
    expect(userRoutes).toContain('/^data:image\\/(?:jpeg|png|webp);base64,/.test(value)');
  });
});
