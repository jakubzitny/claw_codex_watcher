/** @type {import('jest').Config} */
module.exports = {
  rootDir: '.',
  testEnvironment: 'jsdom',
  preset: 'ts-jest',
  testMatch: ['<rootDir>/src/**/*.test.ts'],
  moduleNameMapper: {
    '^@watcher/shared-types$': '<rootDir>/../../packages/shared-types/src/index.ts',
  },
  moduleFileExtensions: ['ts', 'tsx', 'js'],
  clearMocks: true,
}
