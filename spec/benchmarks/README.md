# MessagePack Benchmarks

This directory contains comprehensive benchmarks for the pure Ruby MessagePack implementation.

## Running Benchmarks

### Install Dependencies

```bash
bundle install
```

### Run All Benchmarks

```bash
# Run all benchmark categories
ruby spec/benchmarks/benchmark_suite.rb

# Or run individual benchmark files
ruby spec/benchmarks/primitives_bm.rb
ruby spec/benchmarks/containers_bm.rb
ruby spec/benchmarks/extensions_bm.rb
ruby spec/benchmarks/streaming_bm.rb
ruby spec/benchmarks/realworld_bm.rb
ruby spec/benchmarks/buffer_bm.rb
ruby spec/benchmarks/registry_bm.rb
```

### Run Regression Checks

```bash
# Check for performance regressions against baseline
ruby spec/benchmarks/regression_suite.rb

# Generate new baseline
ruby spec/benchmarks/regression_suite.rb --generate-baseline

# Use custom baseline file
ruby spec/benchmarks/regression_suite.rb --baseline spec/benchmarks/baseline.yml
```

## Benchmark Categories

### Primitives (`primitives_bm.rb`)

Benchmarks for primitive MessagePack types:
- Nil, True, False
- Fixnums (positive/negative)
- Integers (uint8, uint16, uint32, uint64, int8, int16, int32, int64)
- Floats (float32, float64)
- Strings (fixstr, str8, str16, str32)
- Binary data
- Symbols

### Containers (`containers_bm.rb`)

Benchmarks for container types:
- Empty arrays and hashes
- Small arrays (2-10 elements)
- Large arrays (100-1000 elements)
- Nested arrays
- Small hashes (2-10 key-value pairs)
- Large hashes (100-1000 key-value pairs)
- Nested hashes
- Mixed nested structures

### Extensions (`extensions_bm.rb`)

Benchmarks for extension types:
- Timestamp (32, 64, 96 bit)
- Symbol extension
- Custom extension types
- Recursive extension packing

### Streaming (`streaming_bm.rb`)

Benchmarks for streaming operations:
- Small chunks vs large chunks
- Multiple feed operations
- IO streaming (StringIO, File)
- Partial unpacking

### Real World (`realworld_bm.rb`)

Benchmarks for realistic use cases:
- API response structures
- Log entry structures
- Configuration data
- Large dataset serialization
- Comparison with JSON

### Buffer (`buffer_bm.rb`)

Benchmarks for buffer operations:
- Write patterns (small vs large chunks)
- Read performance
- Chunk coalescing impact
- Memory allocation patterns

### Registry (`registry_bm.rb`)

Benchmarks for extension registry:
- Native type lookup overhead
- Registry size impact
- Ancestor search performance
- Cache hit vs miss performance

## Baseline Measurements

The `baseline.yml` file stores reference performance measurements. These are used to detect regressions.

### Updating Baselines

After making performance improvements, update the baseline:

```bash
ruby spec/benchmarks/regression_suite.rb --generate-baseline
git commit spec/benchmarks/baseline.yml -m "Update baseline after optimization"
```

## Understanding Results

### Iterations Per Second (IPS)

Higher values are better. This indicates how many operations can be performed per second.

### Comparison Output

```
Calculating -------------------------------------
                 user     system      total        real
pack nil       1.234M ( ± 3.5%) i/s -      1.567M in   1.272662s
pack true      1.234M ( ± 3.5%) i/s -      1.567M in   1.272662s

Comparison:
                pack nil:    1234567.2 i/s
                pack true:   1234567.1 i/s - same-ish: difference falls within error
```

### Regression Detection

The regression suite will report:
- ✓ **PASS**: Performance is within 95% of baseline
- ✗ **REGRESSION**: Performance dropped below 95% of baseline
- ⚠ **UNEXPECTED**: Performance improved by >2x (verify baseline is correct)

## Optimization Targets

Based on benchmark analysis, the following areas are targeted for optimization:

### High Priority

1. **Buffer Chunk Coalescing** (`lib/messagepack/buffer.rb`)
   - Problem: Each write creates a new chunk
   - Impact: Memory allocation, GC pressure, read performance
   - Benchmark: `spec/benchmarks/buffer_bm.rb`

2. **Extension Registry Fast-Path** (`lib/messagepack/extensions/registry.rb`)
   - Problem: O(n) ancestor search even for native types
   - Impact: CPU cycles per pack operation
   - Benchmark: `spec/benchmarks/registry_bm.rb`

3. **Recursive Packing Allocations** (`lib/messagepack/packer.rb`)
   - Problem: Creates temporary packer for each recursive call
   - Impact: Object allocation count, GC time
   - Benchmark: `spec/benchmarks/extensions_bm.rb`

### Medium Priority

4. **Factory Registry Injection** (`lib/messagepack/factory.rb`)
   - Problem: Uses `instance_variable_set` - fragile
   - Impact: Setup time for packer creation
   - Benchmark: `spec/benchmarks/registry_bm.rb`

5. **Unpacker Module Extraction** (`lib/messagepack/unpacker.rb`)
   - Problem: 900-line file, hard to maintain
   - Impact: No performance change (maintainability only)

## Performance Goals

- **Primitive packing**: 20-30% improvement
- **Buffer operations**: 30-50% improvement
- **Typical real-world use cases**: 10-20% improvement

## Contributing

When adding new benchmarks:

1. Place in the appropriate category file
2. Follow the naming convention: `pack_{{operation}}` or `unpack_{{operation}}`
3. Add baseline values to `baseline.yml`
4. Update this README if adding a new category

## See Also

- [Main README](../../README.adoc) - Project documentation
- [Optimization Plan](../docs/optimization_plan.md) - Detailed optimization roadmap
