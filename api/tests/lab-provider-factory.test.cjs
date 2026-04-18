const path = require('node:path');

const distPath = (relative) =>
  path.join(__dirname, '..', 'dist', 'modules', 'labs', 'providers', relative);

const {
  labProviderFactory,
  resolveLabProviderId,
  LAB_PROVIDER_IDS,
  LAB_PROVIDER_DEFAULT,
  __resetLabProviderFactoryForTests,
  RupaHealthProvider,
  LabCorpProvider,
  LABCORP_CONTRACT_NOT_SIGNED_MESSAGE,
} = require(distPath('index.js'));

describe('labProviderFactory', () => {
  const originalEnv = process.env.LAB_PROVIDER;

  afterEach(() => {
    if (originalEnv === undefined) {
      delete process.env.LAB_PROVIDER;
    } else {
      process.env.LAB_PROVIDER = originalEnv;
    }
    __resetLabProviderFactoryForTests();
  });

  test('exposes the canonical provider id list', () => {
    expect(LAB_PROVIDER_IDS).toEqual(expect.arrayContaining(['rupa', 'labcorp']));
    expect(LAB_PROVIDER_DEFAULT).toBe('rupa');
  });

  test('defaults to rupa when LAB_PROVIDER is unset', () => {
    delete process.env.LAB_PROVIDER;
    __resetLabProviderFactoryForTests();
    const provider = labProviderFactory();
    expect(provider).toBeInstanceOf(RupaHealthProvider);
    expect(provider.id).toBe('rupa');
  });

  test('defaults to rupa for an unknown provider id', () => {
    process.env.LAB_PROVIDER = 'nonsense-vendor';
    __resetLabProviderFactoryForTests();
    expect(resolveLabProviderId('nonsense-vendor')).toBe('rupa');
    expect(labProviderFactory()).toBeInstanceOf(RupaHealthProvider);
  });

  test('returns LabCorpProvider when LAB_PROVIDER=labcorp', () => {
    process.env.LAB_PROVIDER = 'labcorp';
    __resetLabProviderFactoryForTests();
    const provider = labProviderFactory();
    expect(provider).toBeInstanceOf(LabCorpProvider);
    expect(provider.id).toBe('labcorp');
  });

  test('accepts case-insensitive LAB_PROVIDER values', () => {
    process.env.LAB_PROVIDER = 'LABCORP';
    __resetLabProviderFactoryForTests();
    expect(labProviderFactory().id).toBe('labcorp');
  });

  test('caches the provider instance across factory calls', () => {
    process.env.LAB_PROVIDER = 'rupa';
    __resetLabProviderFactoryForTests();
    const first = labProviderFactory();
    const second = labProviderFactory();
    expect(first).toBe(second);
  });

  test('LabCorp stub throws the contract-not-signed error for every method', async () => {
    const provider = new LabCorpProvider();
    const methods = ['listTests', 'listDrawSites', 'createOrder', 'getOrderStatus', 'getResults', 'cancelOrder'];

    expect(LABCORP_CONTRACT_NOT_SIGNED_MESSAGE).toContain('LabCorp API contract not yet signed');

    for (const method of methods) {
      await expect(provider[method]({}, {})).rejects.toThrow(/LabCorp API contract not yet signed/);
    }
  });

  test('RupaHealthProvider exposes auth + URL helpers and defaults to the sandbox base URL', () => {
    const provider = new RupaHealthProvider({ apiKey: 'test-key' });
    expect(provider.id).toBe('rupa');
    expect(provider.displayName).toBe('Rupa Health');
    expect(provider.hasApiKey()).toBe(true);
    expect(provider.getBaseUrl()).toBe('https://api-sandbox.rupahealth.com');
    const headers = provider.buildHeaders('req-123');
    expect(headers.Authorization).toBe('Bearer test-key');
    expect(headers['X-Request-ID']).toBe('req-123');
    expect(provider.buildUrl('/v1/lab_tests')).toBe('https://api-sandbox.rupahealth.com/v1/lab_tests');
    expect(provider.buildUrl('/v1/phlebotomy/locations', { zip: '90210', radius: 25 })).toContain(
      'zip=90210',
    );
  });

  test('RupaHealthProvider.createOrder fails fast when RUPA_API_KEY is missing', async () => {
    const provider = new RupaHealthProvider({ apiKey: '' });
    await expect(
      provider.createOrder({
        patient: {
          userId: 'u1',
          firstName: 'Test',
          lastName: 'Patient',
          dateOfBirth: '1990-01-01',
          sexAtBirth: 'unknown',
          email: 'fake@example.com',
          phone: '555-0100',
          address: { line1: '1 Fake St', city: 'Faketown', state: 'CA', postalCode: '90210' },
        },
        testIds: ['cbc'],
        collectionMethod: 'phlebotomy_site',
        drawSiteId: 'site-1',
      }),
    ).rejects.toThrow(/RUPA_API_KEY is not configured/);
  });

  test('RupaHealthProvider stub throws NotImplementedError for wire-level methods', async () => {
    const provider = new RupaHealthProvider({ apiKey: 'test-key' });
    await expect(provider.listTests()).rejects.toThrow(/not yet implemented/);
    await expect(provider.listDrawSites({ zip: '90210' })).rejects.toThrow(/not yet implemented/);
  });

  test('RupaHealthProvider.createOrder validates collectionMethod + drawSiteId pairing', async () => {
    const provider = new RupaHealthProvider({ apiKey: 'test-key' });
    await expect(
      provider.createOrder({
        patient: {
          userId: 'u1',
          firstName: 'Test',
          lastName: 'Patient',
          dateOfBirth: '1990-01-01',
          sexAtBirth: 'unknown',
          email: 'fake@example.com',
          phone: '555-0100',
          address: { line1: '1 Fake St', city: 'Faketown', state: 'CA', postalCode: '90210' },
        },
        testIds: ['cbc'],
        collectionMethod: 'phlebotomy_site',
        // no drawSiteId on purpose
      }),
    ).rejects.toThrow(/drawSiteId is required/);
  });
});
