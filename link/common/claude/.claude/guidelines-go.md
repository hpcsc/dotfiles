# Organize project

- Follow a domain-driven or feature-based structure rather than organizing by technical layers
- Keep related functionality together to improve code discoverability
- Use a consistent naming convention for packages and files, prefer single-word names
- Use interface to define contract when there are more than 1 possible implementations (test double counted as 1)
- Dependencies should be passed through constructor functions explicitly

# Library Preferences

- `testify` for test assertions
- `https://github.com/caarlos0/env` for loading configuration from environment variables
