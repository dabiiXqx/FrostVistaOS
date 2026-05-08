# RISC-V 二进制工具链使用手册

FrostVistaOS 开发中常用的四个 RISC-V 二进制分析工具详解。

---

## 目录

- [1. riscv64-elf-nm — 符号表查看](#1-riscv64-elf-nm--符号表查看)
- [2. riscv64-elf-objdump — 反汇编与段分析](#2-riscv64-elf-objdump--反汇编与段分析)
- [3. riscv64-elf-readelf — ELF 头信息](#3-riscv64-elf-readelf--elf-头信息)
- [4. grep — 文本搜索搭配](#4-grep--文本搜索搭配)
- [5. 实战组合技](#5-实战组合技)

---

## 1. riscv64-elf-nm — 符号表查看

### 基本用法

```bash
riscv64-elf-nm build/kernel.elf
```

列出 ELF 文件中所有符号（函数名、全局变量、未定义引用等），每行格式：

```
地址 类型 符号名
```

### 符号类型

| 类型 | 含义 | 示例 |
|------|------|------|
| `T` | `.text` 段中的全局函数 | `ffffffc080004c22 T main` |
| `t` | `.text` 段中的静态函数（static，仅文件内可见） | `ffffffc080004be8 t w_mscratch` |
| `D` | `.data` 段中的已初始化全局变量 | `ffffffc080012000 D boot_count` |
| `d` | `.data` 段中的静态变量 | `ffffffc080012040 d cache_size` |
| `B` | `.bss` 段中的未初始化全局变量 | `ffffffc080034b78 B mscratch0` |
| `b` | `.bss` 段中的静态变量 | `ffffffc080035000 b local_buf` |
| `R` | `.rodata` 段中的只读数据 | `ffffffc080013000 R fmt_string` |
| `U` | 未定义符号（需要链接其他 .o 文件） | `U kprintf` |
| `A` | 绝对地址（通常是宏或链接脚本定义的常量） | `ffffffc088000000 A PHYSTOP_HIGH` |

**规则：大小写区分可见性**——大写 = 全局可见（可被其他 .o 引用），小写 = static/局部。

### 常用参数

```bash
# 按地址排序（默认按字母序）
riscv64-elf-nm -n build/kernel.elf

# 只显示外部可见符号（大写类型）
riscv64-elf-nm -g build/kernel.elf

# 只显示未定义符号（找出缺失的引用）
riscv64-elf-nm -u build/kernel.elf

# 显示完整数值（不缩写）
riscv64-elf-nm --radix=x build/kernel.elf

# 显示源文件和行号（需 -g 编译）
riscv64-elf-nm -l build/kernel.elf
```

### 实战示例

```bash
# 找某个函数在哪个地址
riscv64-elf-nm build/kernel.elf | grep m_trap_handler
# ffffffc080007cf0 T m_trap_handler

# 找 mscratch0 在哪个段、多大
riscv64-elf-nm build/kernel.elf | grep mscratch0
# ffffffc080034b78 B mscratch0

# 列出所有 .bss 段的全局符号
riscv64-elf-nm build/kernel.elf | grep ' [BD] '

# 检查是否有未解析的符号（链接失败的常见原因）
riscv64-elf-nm -u build/kernel.elf
```

---

## 2. riscv64-elf-objdump — 反汇编与段分析

### 反汇编（最常用）

```bash
# 反汇编所有段
riscv64-elf-objdump -d build/kernel.elf

# 反汇编 + 混入源码行（需要 -g 编译）
riscv64-elf-objdump -dS build/kernel.elf

# 反汇编指定函数
riscv64-elf-objdump -dS build/kernel.elf | awk '/<main>:/, /^$/'

# 反汇编指定地址范围
riscv64-elf-objdump -d build/kernel.elf \
  --start-address=0xffffffc080004c22 \
  --stop-address=0xffffffc080004d00
```

### 查看段布局（Section Headers）

```bash
riscv64-elf-objdump -h build/kernel.elf
```

输出示例：

```
Idx Name      Size      VMA              LMA
 0 .text     0000a000  ffffffc080000000  0000000080000000
 1 .data     00000d40  ffffffc08000a000  000000008000a000
 2 .bss      0002b3e0  ffffffc08000ad40  000000008000ad40
```

| 列 | 含义 |
|----|------|
| VMA | Virtual Memory Address — 链接时使用的虚拟地址 |
| LMA | Load Memory Address — 实际加载到的物理地址 |
| Size | 段的大小（十六进制字节数） |

**这对内核调试极其关键**：VMA ≠ LMA 说明内核是 Higher Half 设计。物理地址 = `VMA - KERNEL_VIRT_OFFSET`。

### 查看所有符号

```bash
riscv64-elf-objdump -t build/kernel.elf
```

输出比 `nm` 更详细，包含段信息。

### 查看字符串/只读数据

```bash
# 查看 .rodata 段中的字符串
riscv64-elf-objdump -s -j .rodata build/kernel.elf

# 查看 .data 段内容
riscv64-elf-objdump -s -j .data build/kernel.elf
```

### 常用参数组合

```bash
# 完整 dump：反汇编 + 源码 + 所有段内容
riscv64-elf-objdump -D -S -s build/kernel.elf > full_dump.txt

# 只反汇编，去除机器码（更干净）
riscv64-elf-objdump -d --no-show-raw-insn build/kernel.elf

# 显示重定位信息
riscv64-elf-objdump -r build/kernel.elf

# 只反汇编 .text 段
riscv64-elf-objdump -d -j .text build/kernel.elf
```

### 实战示例

```bash
# 定位崩溃地址对应的源码行
riscv64-elf-objdump -dS build/kernel.elf | grep -B5 -A5 '80007ce4:'

# 看一个函数完整实现
riscv64-elf-objdump -dS build/kernel.elf \
  | awk '/m_trap_handler>:/,/^$/' | head -40

# 查某个 CSR 写指令周围的代码
riscv64-elf-objdump -d build/kernel.elf | grep -B2 -A2 'csrw.*mscratch'

# 统计内核各段的实际大小
riscv64-elf-objdump -h build/kernel.elf | grep -E 'text|data|bss'
```

---

## 3. riscv64-elf-readelf — ELF 头信息

### 查看 ELF 文件头

```bash
riscv64-elf-readelf -h build/kernel.elf
```

关键信息：

```
Entry point address: 0xffffffc080000000   ← 内核入口点
Type:               EXEC                  ← 可执行文件
Machine:            RISC-V                ← 目标架构
```

### 查看段头（Section Headers）

```bash
riscv64-elf-readelf -S build/kernel.elf
```

输出所有 section 的 VMA、LMA、大小、对齐等。

### 查看程序头（Program Headers / LOAD 段）

```bash
riscv64-elf-readelf -l build/kernel.elf
```

**这是分析内存布局最重要的命令**。输出示例：

```
Type  Offset    VirtAddr              PhysAddr             FileSiz  MemSiz
LOAD  0x001000  0xffffffc080000000    0x0000000080000000   0x00a000  0x00a000  R E
LOAD  0x00b000  0xffffffc08000a000    0x000000008000a000   0x000d40  0x02c120  RW
```

| 字段 | 含义 |
|------|------|
| VirtAddr | 虚拟地址（VMA）— 代码运行时使用的地址 |
| PhysAddr | 物理地址（LMA）— 实际加载到 RAM 的地址 |
| FileSiz | ELF 文件中占用的字节数 |
| MemSiz | 加载到内存后的字节数（含 .bss，比 FileSiz 大） |
| R E | Read + Execute（.text 段） |
| RW | Read + Write（.data + .bss 段） |

### 查看符号表

```bash
riscv64-elf-readelf -s build/kernel.elf
```

比 `nm` 输出更结构化，每个符号的段索引、大小、类型都有。

### 查看重定位表

```bash
riscv64-elf-readelf -r build/kernel.elf
```

### 检查 ELF 架构和 ABI

```bash
riscv64-elf-readelf -A build/kernel.elf
```

### 实战示例

```bash
# 快速确认内核是 EXEC 还是 DYN 类型
riscv64-elf-readelf -h build/kernel.elf | grep Type

# 查看物理-虚拟地址映射关系
riscv64-elf-readelf -l build/kernel.elf | grep LOAD -A1

# 检查 .bss 段有多大（MemSiz - FileSiz = .bss 大小）
riscv64-elf-readelf -l build/kernel.elf

# 验证入口点地址是否正确
riscv64-elf-readelf -h build/kernel.elf | grep Entry
```

---

## 4. grep — 文本搜索搭配

### 与工具链输出组合

```bash
# 从 nm 输出中找符号
riscv64-elf-nm build/kernel.elf | grep 'panic'

# 从 objdump 中找特定指令
riscv64-elf-objdump -d build/kernel.elf | grep 'csrw.*mscratch'

# 从 readelf 中找 LOAD 段信息
riscv64-elf-readelf -l build/kernel.elf | grep LOAD
```

### 常用参数

```bash
# -n：显示行号
grep -n 'mscratch' arch/riscv/boot/mstart.c

# -r：递归搜索目录
grep -rn 'w_mscratch' arch/ kernel/

# -i：忽略大小写
grep -i 'panic' kernel/fs/*.c

# -v：反向匹配（排除）
riscv64-elf-nm build/kernel.elf | grep ' T ' | grep -v '^0'

# -A/-B/-C：显示匹配行的前后文
riscv64-elf-objdump -d build/kernel.elf | grep -B5 -A10 '<m_trap_handler>:'

# -E：扩展正则
riscv64-elf-nm build/kernel.elf | grep -E '^[0-9a-f]+ [TB] '

# -c：计数
riscv64-elf-nm build/kernel.elf | grep -c ' [tT] '
```

### 组合管道

```bash
# 找到所有全局函数并按地址排序
riscv64-elf-nm build/kernel.elf | grep ' [Tt] ' | sort

# 看某个源文件定义了哪些符号
riscv64-elf-nm -l build/kernel.elf | grep 'proc.c'

# 统计 .bss 中最大的符号
riscv64-elf-nm build/kernel.elf --size-sort | grep ' [bB] ' | tail -20
```

---

## 5. 实战组合技

### 场景 1：内核崩溃，只知道物理地址

```bash
# 已知 mepc = 0x80007ce4（物理地址）
# 先算虚拟地址：0x80007ce4 + KERNEL_VIRT_OFFSET = 0xffffffc080007ce4
# 查反汇编
riscv64-elf-objdump -dS build/kernel.elf | grep -B10 -A10 'ffffffc080007ce4'
```

### 场景 2：确认一个全局变量在哪个段、物理地址是什么

```bash
# 查 VMA
riscv64-elf-nm build/kernel.elf | grep mscratch0
# ffffffc080034b78 B mscratch0

# 查段布局，计算物理地址
riscv64-elf-readelf -l build/kernel.elf | grep -A1 LOAD
# .bss 的物理起始地址 + (VMA - .bss VMA 起始) = 物理地址
```

### 场景 3：检查是否有函数缺少声明

```bash
# 看有多少 static 函数（小写 t）
riscv64-elf-nm build/kernel.elf | grep ' [tT] ' | wc -l

# 对比全局函数，看是否有应该 static 但没加的
riscv64-elf-nm build/kernel.elf | grep ' [T] '
```

### 场景 4：分析内核镜像大小

```bash
# .text + .data + .bss 各自多大
riscv64-elf-objdump -h build/kernel.elf | grep -E '\.text|\.data|\.bss'

# 总大小
riscv64-elf-size build/kernel.elf
```

### 场景 5：切换构建后验证符号变化

```bash
# Release vs Debug 对比
make BUILD=release && cp build/kernel.elf /tmp/kernel_release.elf
make clean && make BUILD=debug && cp build/kernel.elf /tmp/kernel_debug.elf

diff <(riscv64-elf-nm /tmp/kernel_release.elf | sort) \
     <(riscv64-elf-nm /tmp/kernel_debug.elf | sort)
```

### 场景 6：追踪函数调用链

```bash
# 找一个函数被哪些地方引用
riscv64-elf-objdump -d build/kernel.elf | grep 'jal.*<w_mscratch>'
```

### 场景 7：快速定位异常指令的源码行

```bash
addr=0xffffffc080007ce4
riscv64-elf-addr2line -e build/kernel.elf $addr
```

（注意：需要 `-g` 编译，`addr2line` 才能输出源码行号）

---

## 附录：其他有用工具

```bash
# 查看 ELF 各段大小
riscv64-elf-size build/kernel.elf

# 查看 ELF 中的字符串
riscv64-elf-strings build/kernel.elf

# 去除调试符号，减小镜像体积
riscv64-elf-strip build/kernel.elf

# 二进制文件对比
riscv64-elf-objcopy -O binary build/kernel.elf build/kernel.bin
```
