# Contributing to TrainCam

Thank you for your interest in contributing to TrainCam! This project aims to make model railroad cab-view cameras accessible to hobbyists of all skill levels.

## How to Contribute

### Reporting Bugs

1. Check [existing issues](https://github.com/djdefi/traincam-ncngrr/issues) first
2. Open a new issue with:
   - Clear title describing the problem
   - Steps to reproduce
   - Expected vs actual behavior
   - Hardware details (Pi Zero, ESP32-CAM, etc.)
   - Relevant logs

### Suggesting Features

Open an issue with the `enhancement` label. Describe:
- What problem it solves
- Your proposed solution
- Alternatives you considered

### Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Run tests: `./tests/run_tests.sh`
5. Run linting: `./scripts/lint.sh`
6. Commit with clear messages
7. Push and open a PR

### Code Style

- **Shell scripts**: Follow [ShellCheck](https://www.shellcheck.net/) recommendations
- **Ansible**: Follow [ansible-lint](https://ansible-lint.readthedocs.io/) rules
- **Arduino/C++**: Use consistent indentation (2 spaces)
- **Documentation**: Keep it accessible to beginners

### Areas We Need Help

- 📹 **Streaming improvements** - Lower latency, better quality
- 📱 **Mobile app** - Native iOS/Android viewer
- 🔧 **Hardware designs** - 3D printable mounts, PCB layouts
- 📖 **Documentation** - Tutorials, translations
- 🧪 **Testing** - More test coverage, CI improvements
- 🌐 **ESP32 features** - mDNS, better WebUI

## Development Setup

```bash
# Clone the repo
git clone https://github.com/djdefi/traincam-ncngrr.git
cd traincam-ncngrr

# Run tests
./tests/run_tests.sh

# Run linting (requires ansible-lint and shellcheck)
./scripts/lint.sh
```

## Questions?

Open an issue or start a discussion. We're happy to help!

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
