const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..', '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

describe('release policy contract', () => {
  test('release policy file exists with the required keys', () => {
    const releasePolicyPath = path.join(repoRoot, 'config/release-policy.json');
    expect(fs.existsSync(releasePolicyPath)).toBe(true);

    const releasePolicy = JSON.parse(fs.readFileSync(releasePolicyPath, 'utf8'));
    expect(releasePolicy).toMatchObject({
      version: expect.any(String),
      minimumSupportedVersion: expect.any(String),
      forceUpgrade: expect.any(Boolean),
      publishedAt: expect.any(String),
      releaseNotes: expect.any(Array),
      environment: expect.any(String),
    });
  });

  test('protected client release middleware returns upgrade required semantics', () => {
    const clientRelease = read('api/src/middleware/clientRelease.ts');
    expect(clientRelease).toContain('StatusCodes.UPGRADE_REQUIRED');
    expect(clientRelease).toContain('missing_client_version');
    expect(clientRelease).toContain('Client update required');
    expect(clientRelease).toContain('getRemoteConfigPayload(clientRelease)');
  });
});
