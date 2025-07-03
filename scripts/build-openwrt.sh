#!/bin/bash
set -e

# 获取版本号
VERSION=${1:-$(date +'%Y%m%d')}
BUILD_DIR="$HOME/openwrt_build"
REPO_DIR="$PWD"

echo "=== 开始内存优化编译 (版本: $VERSION) ==="

# 1. 配置环境
export FORCE_UNSAFE_CONFIGURE=1
export CCACHE_DIR="$HOME/.ccache"
export CCACHE_MAXSIZE="2G"
mkdir -p "$CCACHE_DIR"

# 2. 进入源码目录
cd "$REPO_DIR"

# 3. 应用内存优化配置
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

# 4. 更新 feeds
echo "更新 feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

# 5. 应用内存优化补丁
echo "应用内存优化补丁..."
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
[ -f patches/memory-optimize.patch ] && patch -p1 < patches/memory-optimize.patch

# 6. 下载依赖
echo "下载依赖库..."
make download -j$(nproc) || make download -j8 V=s

# 7. 编译固件
echo "开始编译固件..."
make -j$(nproc) V=s || make -j1 V=s

# 8. 收集输出文件
mkdir -p "$BUILD_DIR"
find bin/targets -name '*.bin' -exec cp -v {} "$BUILD_DIR" \;

# 9. 添加版本信息
for file in "$BUILD_DIR"/*.bin; do
    new_name="${file%.*}_MEMOPT_$VERSION.bin"
    mv "$file" "$new_name"
    echo "生成: $(basename "$new_name")"
done

# 10. 生成报告
cat > "$BUILD_DIR/build-report.md" << EOF
# OpenWrt 内存优化固件报告
**版本**: $VERSION  
**编译时间**: $(date)  

## 内存优化配置
- **内核配置**: LTO + Size优化 + Slab限制
- **服务优化**: dnsmasq → odhcpd, uhttpd → lighttpd
- **内存压缩**: zRAM 启用

## 关键参数
\`\`\`
$(grep -E 'CONFIG_(SLAB|LTO|ZRAM|CACHE|TCP)' .config)
\`\`\`

## 输出文件
$(ls -lh "$BUILD_DIR"/*.bin)
EOF

echo "=== 编译完成! 固件已保存至: $BUILD_DIR ==="
