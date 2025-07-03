#!/bin/bash
set -e

# 获取版本号
VERSION=${1:-snapshot}
BUILD_DIR="$HOME/openwrt_build"
REPO_DIR=$(pwd)

echo "=== 开始内存优化编译 (版本: $VERSION) ==="

# 配置环境
export FORCE_UNSAFE_CONFIGURE=1
[ -z "$CCACHE_DIR" ] && export CCACHE_DIR="$HOME/.ccache"
export CCACHE_MAXSIZE="2G"
mkdir -p "$CCACHE_DIR"

# 应用内存优化配置
cat > .config << 'EOF'
CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_qihoo_360v6=y

# 内存优化核心配置
CONFIG_SLAB_MERGE_DEFAULT=y
CONFIG_DCACHE_WORD_ACCESS=y
CONFIG_LIMIT_DENTRY_CACHE_SIZE=y
CONFIG_DCACHE_MAX=16384
CONFIG_TCP_CONG_CUBIC=y
CONFIG_NET_SCHED=n
CONFIG_CC_OPTIMIZE_FOR_SIZE=y
CONFIG_KERNEL_LTO=y
CONFIG_STRIP_KERNEL_EXPORTS=y

# 服务精简
CONFIG_PACKAGE_dnsmasq_full=n
CONFIG_PACKAGE_odhcpd=y
CONFIG_PACKAGE_uhttpd=n
CONFIG_PACKAGE_lighttpd=y
CONFIG_PACKAGE_logd=n

# 内存压缩
CONFIG_PACKAGE_zram-swap=y
CONFIG_PACKAGE_kmod-zram=y
EOF

# 更新 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 应用内存优化补丁
if [ ! -f patches/memory-optimize.patch ]; then
  cat > patches/memory-optimize.patch << 'EOF'
--- a/net/core/skbuff.c
+++ b/net/core/skbuff.c
@@ -1000,6 +1000,7 @@
        if (unlikely(!skb))
                goto out;
        prefetchw(skb);
+       memset(skb, 0, offsetof(struct sk_buff, tail));
 }
EOF
  patch -p1 < patches/memory-optimize.patch
fi

# 下载依赖
make download -j$(nproc) || make download -j4 V=s

# 编译固件
make -j$(($(nproc) + 1)) V=s || make -j2 V=s

# 收集输出文件
mkdir -p "$BUILD_DIR"
find bin/targets -name '*.bin' -exec cp -v {} "$BUILD_DIR" \;

# 添加版本信息
for file in "$BUILD_DIR"/*.bin; do
  filename=$(basename "$file")
  extension="${filename##*.}"
  new_name="${filename%.*}_MEMOPT_$VERSION.$extension"
  mv "$file" "$BUILD_DIR/$new_name"
  echo "生成: $new_name"
done

# 生成报告
cat > "$BUILD_DIR/build-report.md" << EOF
# OpenWrt 内存优化固件报告
**版本**: $VERSION  
**编译时间**: $(date)  
**Git Commit**: $(git rev-parse --short HEAD)  

## 优化配置
\`\`\`config
$(grep -E 'CONFIG_(SLAB|LTO|ZRAM|CACHE|TCP)' .config)
\`\`\`

## 包含固件
$(ls -lh "$BUILD_DIR"/*.bin | awk '{print "- " $9 " (" $5 ")"}')
EOF

echo "=== 编译完成! 固件已保存至: $BUILD_DIR ==="
