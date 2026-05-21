# frozen_string_literal: true

begin
  require "wasmtime"
  WASMTIME_LOADED = true
rescue LoadError
  WASMTIME_LOADED = false
end

module Relaton
  module Un
    module TokenGenerator
      WASMTIME_AVAILABLE = WASMTIME_LOADED
      WASM_PATH = File.join(__dir__, "wasm_v_bg.wasm")
      DOMAIN = "documents.un.org"

      # Generates an auth token for the UN documents API.
      # Tokens are cached per-minute since the WASM output changes each minute.
      # @return [String] decimal string representation of the i64 token
      def self.generate
        unless WASMTIME_AVAILABLE
          warn "[relaton-un] wasmtime gem is not available on this platform. Token generation is disabled."
          return nil
        end

        now = Time.now.utc
        key = [now.year, now.month, now.day, now.hour, now.min]
        return @cached_token if @cached_key == key && @cached_token

        @cached_key = key
        @cached_token = call_wasm(*key)
      end

      def self.call_wasm(year, month, day, hour, minute) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
        engine = Wasmtime::Engine.new
        mod = Wasmtime::Module.new(engine, File.binread(WASM_PATH))
        store = Wasmtime::Store.new(engine)
        linker = Wasmtime::Linker.new(engine)

        heap = Heap.new
        fake_window = Object.new
        fake_location = Object.new

        # Pre-allocate well-known objects in the heap
        heap.alloc(fake_window)   # index 4
        heap.alloc(fake_location) # index 5

        define_imports(linker, heap, fake_window, fake_location)

        instance = linker.instantiate(store, mod)
        result = instance.invoke("check", year, month, day, hour, minute)
        result.to_s
      end

      def self.define_imports(linker, heap, fake_window, fake_location) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        linker.func_new("wbg", "__wbindgen_object_drop_ref", [:i32], []) do |_caller, idx|
          heap.drop(idx)
        end

        linker.func_new("wbg", "__wbg_instanceof_Window_acc97ff9f5d2c7b4", [:i32], [:i32]) do |_caller, _idx|
          1
        end

        linker.func_new("wbg", "__wbg_location_8cc8ccf27e342c0a", [:i32], [:i32]) do |_caller, _idx|
          heap.alloc(fake_location)
        end

        define_host_import(linker, heap)

        linker.func_new("wbg", "__wbg_newnoargs_b5b063fc6c2f0376", [:i32, :i32], [:i32]) do |_caller, _ptr, _len|
          heap.alloc(Object.new)
        end

        linker.func_new("wbg", "__wbg_call_97ae9d8645dc388b", [:i32, :i32], [:i32]) do |_caller, _func_idx, _this_idx|
          heap.alloc(fake_window)
        end

        linker.func_new("wbg", "__wbindgen_object_clone_ref", [:i32], [:i32]) do |_caller, idx|
          heap.alloc(heap.get(idx))
        end

        %w[
          __wbg_self_6d479506f72c6a71
          __wbg_window_f2557cc78490aceb
          __wbg_globalThis_7f206bda628d5286
          __wbg_global_ba75c50d1cf384f4
        ].each do |name|
          linker.func_new("wbg", name, [], [:i32]) do |_caller|
            heap.alloc(fake_window)
          end
        end

        linker.func_new("wbg", "__wbindgen_is_undefined", [:i32], [:i32]) do |_caller, idx|
          heap.get(idx) == :undefined ? 1 : 0
        end

        linker.func_new("wbg", "__wbindgen_debug_string", [:i32, :i32], []) do |_caller, _ret_ptr, _idx|
          # no-op
        end

        linker.func_new("wbg", "__wbindgen_throw", [:i32, :i32], []) do |caller, ptr, len|
          mem = caller.export("memory").to_memory
          msg = mem.read(ptr, len)
          raise msg
        end
      end

      # The host import writes the domain string into WASM memory.
      # It allocates space via __wbindgen_malloc, copies the UTF-8 bytes,
      # and writes (ptr, len) at the return pointer address.
      def self.define_host_import(linker, _heap)
        linker.func_new("wbg", "__wbg_host_f82dbbd8bb5ef24a", [:i32, :i32], []) do |caller, ret_ptr, _loc_idx|
          mem = caller.export("memory").to_memory
          malloc_fn = caller.export("__wbindgen_malloc").to_func
          host_bytes = DOMAIN.encode("utf-8")
          ptr = malloc_fn.call(host_bytes.bytesize)
          mem.write(ptr, host_bytes)
          mem.write(ret_ptr, [ptr, host_bytes.bytesize].pack("V2"))
        end
      end

      # Manages a slab-allocated heap of Ruby objects indexed by i32,
      # mirroring wasm-bindgen's JS object heap.
      class Heap
        BUILTINS = 36

        def initialize
          # Indices 0-3 mirror wasm-bindgen's builtin slots:
          # 0 = undefined, 1 = null, 2 = true, 3 = false
          @slab = [:undefined, nil, true, false]
          @free_head = @slab.length
        end

        def get(idx)
          @slab[idx]
        end

        def alloc(obj)
          if @free_head >= @slab.length
            @slab << (@slab.length + 1)
          end
          idx = @free_head
          @free_head = @slab[idx]
          @slab[idx] = obj
          idx
        end

        def drop(idx)
          return if idx < BUILTINS

          @slab[idx] = @free_head
          @free_head = idx
        end
      end

      private_class_method :call_wasm, :define_imports, :define_host_import
    end
  end
end
