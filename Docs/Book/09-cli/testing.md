# CLI: Testing

The Dext CLI features a sophisticated integrated test runner.

## Running Tests

```bash
dext test
```
This will search for all `[TestFixture]` in your application and execute the test units.

## Code Coverage

Dext integrates with DelphiCodeCoverage to generate precise metrics:

```bash
dext test --coverage
```

### Report Options

- **HTML**: Visual report for humans.
- **XML**: For CI/CD integration (SonarQube, Azure DevOps).
- **JSON**: For custom processing.

```bash
# Generate HTML in a specific directory
dext test --coverage --html --output-dir .\reports
```

## Test Filtering

Run only the tests you are currently modifying:

```bash
# Filter by class or method name
dext test --filter TUserServiceTests
```

## Quality Gates (Thresholds)

You can fail the build if code coverage is lower than expected:

```bash
# Fails if coverage is below 80%
dext test --coverage --threshold 80
```

Below the threshold, and also when the suite fails, the process exits with code 1.

---

[← Scaffolding](scaffolding.md) | [Next: Dashboard →](dashboard.md)
