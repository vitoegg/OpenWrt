# BBRv3 Patch

目标版本：

- ImmortalWrt commit / branch：见 `profiles/upstream.conf`
- Kernel patch version: `6.12`

Patch 由 `.github/workflows/refresh-bbr-patches.yml` 随上游 commit 自动 refresh 并回写，下文的手动流程仅用于首次导入或排查 reject。

来源版本：

- r4s_build_script branch: `linux-6.12`
- r4s_build_script commit: `27b554ac3126b1080d1770b7f29b35bc0e0a9955`
- Source path: `openwrt/patch/kernel-6.12/bbr3`

本目录只保留 20 个内核 BBRv3 Patch，不包含 r4s 的 3 个 iproute2 Patch。

## 使用位置

本仓库通过 `scripts/customize/patches.sh` 在编译时自动复制这些 Patch。

在 IMM 源码树中放入：

```sh
target/linux/generic/backport-6.12/010-bbr3-*.patch
```

OpenWrt/IMM 内核 Patch 顺序是：

```text
generic-backport -> generic -> generic-hack -> platform
```

因此 BBRv3 应放在 `generic/backport-6.12`，并且文件名前缀保持 `010-bbr3-*`，让它先于 IMM 自带 backport patch 应用。

## 生成流程

```sh
git clone --single-branch --branch openwrt-25.12 https://github.com/immortalwrt/immortalwrt.git imm
cd imm
git checkout <WRT_COMMIT>

cp /path/to/r4s_build_script/openwrt/patch/kernel-6.12/bbr3/010-bbr3-*.patch \
  target/linux/generic/backport-6.12/

./scripts/feeds update -a
./scripts/feeds install -a
cat /path/to/OpenWrt/profiles/common/build.config /path/to/OpenWrt/profiles/router/build.config > .config
make defconfig

make target/linux/prepare V=s
make target/linux/clean V=s
make target/linux/refresh V=s
```

验证结果：

- `make target/linux/prepare V=s`：20 个 BBRv3 Patch 全部 apply 成功，无 reject。
- `make target/linux/refresh V=s`：20 个 BBRv3 Patch 全部 quilt refresh 成功。
- refresh 后有 12 个 BBRv3 Patch 仅变更 hunk 上下文/行号；实际代码增删内容与 r4s 原始 Patch 一致。

## 内核变更时如何适配

先确认目标内核：

```sh
grep -n '^KERNEL_PATCHVER' target/linux/x86/Makefile
grep -n '^LINUX_VERSION-6.12' target/linux/generic/kernel-6.12
```

适配规则：

- 仍是 `6.12.x`：继续以 r4s `linux-6.12` 的 `bbr3` 为种子，复制到 `target/linux/generic/backport-6.12/`，跑 `prepare` 和 `refresh`。
- 变为 `6.18.x`：不要硬套 6.12 Patch，改用 r4s 当前 `kernel-6.18/bbr3`。6.18 和 6.12 的 BBRv3 Patch 存在真实 API/上下文差异。
- `prepare` 出现 `.rej`：在 `build_dir/.../linux-*/` 查看 reject，对照目标内核当前文件手动更新对应 Patch，再重新 `prepare`。
- `refresh` 后需要确认语义未漂移：比较 Patch 中实际 `+`/`-` 代码行，而不是只看 hunk 行号。

最小验收标准：

```sh
make target/linux/prepare V=s
find build_dir -name '*.rej' -o -name '*.orig'
make target/linux/refresh V=s
```

`find` 不应返回 reject 文件。
