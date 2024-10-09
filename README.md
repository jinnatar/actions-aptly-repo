# <!--name-->Aptly deb repo creator<!--/name-->
<!--description-->
Create ad-hoc deb repositories into GitHub artifacts.
These can be published onwards into GitHub Pages.

The current v1 supports stateless repos, i.e. where the contents of 
the run create a blank slate every time. The intent is to build upon 
this for an "import & extend" workflow that allows preserving state.
<!--/description-->

## Inputs
<!--inputs-->
| Name              | Description                                                                                                                                                                                                                                                                                                                                                        | Required | Default                           |
|-------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|-----------------------------------|
| `name`            | "Short name of the project used as a slug to refer to your repo."<br>                                                                                                                                                                                                                                                                                              | `true`   | ` `                               |
| `prefix`          | Repo prefix in the published structure.<br>Relevant if you wish to separate say ubuntu & debian completely.<br>                                                                                                                                                                                                                                                    | `true`   | `.`                               |
| `repos`           | Repository definitions to create. Provided as a comma separated csv.<br>The architecture list should be quoted and comma separated.<br>Fields are in order: distribution, category, architectures, filesystem glob of debs.<br>The default thus creates a single distribution of "bookworm", category "stable" for amd64 of all debs in the current directory.<br> | `true`   | `bookworm,stable,"amd64",./*.deb` |
| `gpg_key_id`      | ID of the GPG public key to use for signing.<br>Useful for definining a signing specific subkey.<br>                                                                                                                                                                                                                                                               | `true`   | ` `                               |
| `gpg_private_key` | Armored gpg private key to sign the repo with.                                                                                                                                                                                                                                                                                                                     | `true`   | ` `                               |
| `gpg_passphrase`  | The passphrase of the provided GPG key.                                                                                                                                                                                                                                                                                                                            | `true`   | ` `                               |
| `GITHUB_TOKEN`    | A GitHub token, available in the secrets.GITHUB_TOKEN working-directory variable.<br>                                                                                                                                                                                                                                                                              | `false`  | `${{ github.token }}`             |
<!--/inputs-->

## Outputs
<!--outputs-->
| Name | Description |
|------|-------------|
<!--/outputs-->

## Usage
<!--usage action="org/repo" version="v1"-->

A simple example without using prefixes or matrix building:

```yaml
jobs:
  create-demo-repo:
    name: Create demo repo
    runs-on: ubuntu-24.04
    steps:
      - name: Checkout
        uses: actions/checkout@v4  # Or otherwise make deb files available, say from an earlier build step's artifacts.
      - name: Create repo
        uses: jinnatar/actions-aptly-repo@v1
        with:
          name: demo
          repos: |
              noble,stable,\"amd64,arm64\",debs/stable-ubuntu-24.04-*-unknown-linux-gnu/*.deb
              jammy,stable,\"amd64,arm64\",debs/stable-ubuntu-22.04-*-unknown-linux-gnu/*.deb
              noble,nightly,\"amd64,arm64\",debs/nightly-ubuntu-24.04-*-unknown-linux-gnu/*.deb
              bookworm,stable,\"amd64,arm64\",debs/stable-debian-12-*-unknown-linux-gnu/*.deb
              bookworm,nightly,\"amd64,arm64\",debs/nightly-debian-12-*-unknown-linux-gnu/*.deb
          gpg_private_key: "${{ secrets.GPG_PRIVATE_KEY }}"
          gpg_passphrase: "${{ secrets.PASSPHRASE }}"
```

An example APT `demo-repo.list` would thus be:
```
deb [arch=amd64,arm64 signed-by=/etc/apt/trusted.gpg.d/demo.gpg] https://repo.example.com noble stable
```

A more complex example that splits Ubuntu & Debian via a matrix into separate prefixes
and only deploys the `nightly` category for latest LTS versions. Splitting by prefix is however not mandatory
as Aptly 1.6.0 is used that supports multi-distro publishing without conflicts.
```yaml
jobs:
  create-demo-repo:
    name: Create adhoc repos
    strategy:
      matrix:
        prefix:
          - name: ubuntu
            repos: |
              noble,stable,\"amd64,arm64\",debs/stable-ubuntu-24.04-*-unknown-linux-gnu/*.deb
              jammy,stable,\"amd64,arm64\",debs/stable-ubuntu-22.04-*-unknown-linux-gnu/*.deb
              noble,nightly,\"amd64,arm64\",debs/nightly-ubuntu-24.04-*-unknown-linux-gnu/*.deb
          - name: debian
            repos: |
              bookworm,stable,\"amd64,arm64\",debs/stable-debian-12-*-unknown-linux-gnu/*.deb
              bookworm,nightly,\"amd64,arm64\",debs/nightly-debian-12-*-unknown-linux-gnu/*.deb
      fail-fast: false
    runs-on: ubuntu-24.04
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Create repo
        uses: jinnatar/actions-aptly-repo@v1
        with:
          name: demo
          prefix: "${{ matrix.prefix.name }}"
          repos: "${{ matrix.prefix.repos }}"
          gpg_private_key: "${{ secrets.GPG_PRIVATE_KEY }}"
          gpg_passphrase: "${{ secrets.PASSPHRASE }}"
```

An example APT `demo-repo.list` would thus be:
```
deb [arch=amd64,arm64 signed-by=/etc/apt/trusted.gpg.d/demo.gpg] https://repo.example.com/ubuntu noble stable
```

<!--/usage-->
