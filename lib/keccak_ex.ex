defmodule KeccakEx do
  @moduledoc """
  Implementation of Keccak in pure Elixir.
  """

  import Bitwise
  import Binary, only: [take: 2, pad_trailing: 2, trim_trailing: 1]

  @constants [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
    0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
    0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
  ]

  @initial_state [
    0x0000000000000000, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0x0000000000000000,
    0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
    0xFFFFFFFFFFFFFFFF, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
    0xFFFFFFFFFFFFFFFF, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
    0x0000000000000000, 0xFFFFFFFFFFFFFFFF, 0x0000000000000000, 0x0000000000000000,
    0xFFFFFFFFFFFFFFFF, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
    0x0000000000000000
  ]

  @invalidate 0xFFFFFFFFFFFFFFFF

  defstruct input: nil,
            input_length: nil,
            buffer: nil,
            state: nil,
            input_cut: nil,
            digest_length: nil,
            block_length: nil

  @spec hash_256(bitstring()) :: nil | <<_::8, _::_*1>>
  @doc """
  Returns the keccak hash 256
  """
  def hash_256(input) do
    data = %__MODULE__{
      input: input,
      input_length: 0,
      buffer: pad_trailing(<<0>>, 32),
      state: @initial_state,
      digest_length: 32,
      block_length: 200 - 2 * 32
    }

    hash(data)
  end

  @spec hash_512(bitstring()) :: nil | <<_::8, _::_*1>>
  @doc """
  Returns the keccak hash 512
  """
  def hash_512(input) do
    data = %__MODULE__{
      input: input,
      input_length: 0,
      buffer: pad_trailing(<<0>>, 64),
      state: @initial_state,
      digest_length: 64,
      block_length: 200 - 2 * 64
    }

    hash(data)
  end

  defp hash(%__MODULE__{} = data) do
    data
    |> update(0, 0, byte_size(data.input))
    |> digest()
  end

  defp update(%__MODULE__{} = value, input_length, offset, length) when length > 0 do
    copy_length = get_copy_length(value, input_length, length)

    copied = copy(value.input, offset, value.buffer, input_length, copy_length)

    data = %{value | buffer: copied, input_cut: copied, input_length: input_length + copy_length}

    if (input_length + copy_length) == value.block_length do
      data
      |> process_block()
      |> update(0, offset + copy_length, length - copy_length)
    else
      data
      |> update(input_length + copy_length, offset + copy_length, length - copy_length)
    end
  end

  defp update(value, _input_length, _offset, _length), do: value

  defp digest(%__MODULE__{} = value) do
    value
    |> padding()
    |> process_block()
    |> encode()
  end

  defp padding(%__MODULE__{} = value) do
    fix = if (value.input_length + 1) == byte_size(value.buffer) do
      value.buffer
      |> binary_part(0, value.input_length)
      |> set_value(<<0x81>>)
    else
      value.buffer
      |> binary_part(0, value.input_length)
      |> set_value(<<1>>)
      |> pad_trailing(value.block_length)
      |> take(value.block_length - 1)
      |> set_value(<<0x80>>)
    end

    %{value | buffer: fix, input_cut: fix}
  end

  defp copy(source, source_index, destination, destination_index, length) do
    data = binary_part(source, source_index, length)

    destination_trim = destination |> trim_trailing()

    if byte_size(destination_trim) == 0 do
      data |> pad_trailing(byte_size(destination))
    else
      start = binary_part(destination, 0, destination_index)
      final = binary_part(destination, destination_index + length, byte_size(destination) - destination_index - length)
      start <> data <> final
    end
  end

  defp get_copy_length(%__MODULE__{} = data, input_length, length) do
    copy_length = data.block_length - input_length
    if copy_length > length do
      length
    else
      copy_length
    end
  end

  defp process_block(%__MODULE__{} = data) do
    data
    |> process_block_decode_loop(0)
    |> process_block_loop(0)
  end

  defp encode(%__MODULE__{} = data) do
    a01 = data.state |> Enum.at(1)
    a02 = data.state |> Enum.at(2)
    a08 = data.state |> Enum.at(8)
    a12 = data.state |> Enum.at(12)
    a17 = data.state |> Enum.at(17)
    a20 = data.state |> Enum.at(20)

    state =
      data.state
      |> List.replace_at(1,  ~~~a01 &&& @invalidate)
      |> List.replace_at(2,  ~~~a02 &&& @invalidate)
      |> List.replace_at(8,  ~~~a08 &&& @invalidate)
      |> List.replace_at(12, ~~~a12 &&& @invalidate)
      |> List.replace_at(17, ~~~a17 &&& @invalidate)
      |> List.replace_at(20, ~~~a20 &&& @invalidate)

    encode_loop(data, state, nil, 0)
  end

  defp encode_loop(%__MODULE__{} = data, state, current, index) when index < data.digest_length do
    <<a::8, b::8, c::8, d::8, e::8, f::8, g::8, h::8>> = <<Enum.at(state, index >>> 3)::64>>

    replaced = if current == nil do
      <<h, g, f, e, d, c, b, a>>
    else
      current <> <<h, g, f, e, d, c, b, a>>
    end

    encode_loop(data, state, replaced, index + 8)
  end

  defp encode_loop(_data, _state, current, _index), do: current

  defp set_value(buffer, value), do: buffer <> value

  defp process_block_loop(%__MODULE__{state: state} = value, index) when index < 24 do
    [
      a00,
      a01,
      a02,
      a03,
      a04,
      a05,
      a06,
      a07,
      a08,
      a09,
      a10,
      a11,
      a12,
      a13,
      a14,
      a15,
      a16,
      a17,
      a18,
      a19,
      a20,
      a21,
      a22,
      a23,
      a24
    ] = state

    tt0 = bxor(a01, a06)
    tt1 = bxor(a11, a16)
    tt0 = bxor(tt0, a21) |> bxor(tt1)
    tt0 = (tt0 <<< 1 &&& @invalidate) ||| (tt0 >>> 63)
    tt2 = bxor(a04, a09)
    tt3 = bxor(a14, a19)
    tt0 = bxor(tt0, a24)
    tt2 = bxor(tt2, tt3)
    t0 =  bxor(tt0, tt2)

    tt0 = bxor(a02, a07)
    tt1 = bxor(a12, a17)
    tt0 = bxor(tt0, a22) |> bxor(tt1)
    tt0 = (tt0 <<< 1 &&& @invalidate) ||| (tt0 >>> 63)
    tt2 = bxor(a00, a05)
    tt3 = bxor(a10, a15)
    tt0 = bxor(tt0, a20)
    tt2 = bxor(tt2, tt3)
    t1 =  bxor(tt0, tt2)

    tt0 = bxor(a03, a08)
    tt1 = bxor(a13, a18)
    tt0 = bxor(tt0, a23) |> bxor(tt1)
    tt0 = (tt0 <<< 1 &&& @invalidate) ||| (tt0 >>> 63)
    tt2 = bxor(a01, a06)
    tt3 = bxor(a11, a16)
    tt0 = bxor(tt0, a21)
    tt2 = bxor(tt2, tt3)
    t2 =  bxor(tt0, tt2)

    tt0 = bxor(a04, a09)
    tt1 = bxor(a14, a19)
    tt0 = bxor(tt0, a24) |> bxor(tt1)
    tt0 = (tt0 <<< 1 &&& @invalidate) ||| (tt0 >>> 63)
    tt2 = bxor(a02, a07)
    tt3 = bxor(a12, a17)
    tt0 = bxor(tt0, a22)
    tt2 = bxor(tt2, tt3)
    t3 =  bxor(tt0, tt2)

    tt0 = bxor(a00, a05)
    tt1 = bxor(a10, a15)
    tt0 = bxor(tt0, a20) |> bxor(tt1)
    tt0 = (tt0 <<< 1 &&& @invalidate) ||| (tt0 >>> 63)
    tt2 = bxor(a03, a08)
    tt3 = bxor(a13, a18)
    tt0 = bxor(tt0, a23)
    tt2 = bxor(tt2, tt3)
    t4 =  bxor(tt0, tt2)

    a00 = bxor(a00, t0)
    a05 = bxor(a05, t0)
    a10 = bxor(a10, t0)
    a15 = bxor(a15, t0)
    a20 = bxor(a20, t0)
    a01 = bxor(a01, t1)
    a06 = bxor(a06, t1)
    a11 = bxor(a11, t1)
    a16 = bxor(a16, t1)
    a21 = bxor(a21, t1)
    a02 = bxor(a02, t2)
    a07 = bxor(a07, t2)
    a12 = bxor(a12, t2)
    a17 = bxor(a17, t2)
    a22 = bxor(a22, t2)
    a03 = bxor(a03, t3)
    a08 = bxor(a08, t3)
    a13 = bxor(a13, t3)
    a18 = bxor(a18, t3)
    a23 = bxor(a23, t3)
    a04 = bxor(a04, t4)
    a09 = bxor(a09, t4)
    a14 = bxor(a14, t4)
    a19 = bxor(a19, t4)
    a24 = bxor(a24, t4)
    a05 = (a05 <<< 36 &&& @invalidate) ||| (a05 >>> (64 - 36))
    a10 = (a10 <<<  3 &&& @invalidate) ||| (a10 >>> (64 -  3))
    a15 = (a15 <<< 41 &&& @invalidate) ||| (a15 >>> (64 - 41))
    a20 = (a20 <<< 18 &&& @invalidate) ||| (a20 >>> (64 - 18))
    a01 = (a01 <<<  1 &&& @invalidate) ||| (a01 >>> (64 -  1))
    a06 = (a06 <<< 44 &&& @invalidate) ||| (a06 >>> (64 - 44))
    a11 = (a11 <<< 10 &&& @invalidate) ||| (a11 >>> (64 - 10))
    a16 = (a16 <<< 45 &&& @invalidate) ||| (a16 >>> (64 - 45))
    a21 = (a21 <<<  2 &&& @invalidate) ||| (a21 >>> (64 -  2))
    a02 = (a02 <<< 62 &&& @invalidate) ||| (a02 >>> (64 - 62))
    a07 = (a07 <<<  6 &&& @invalidate) ||| (a07 >>> (64 -  6))
    a12 = (a12 <<< 43 &&& @invalidate) ||| (a12 >>> (64 - 43))
    a17 = (a17 <<< 15 &&& @invalidate) ||| (a17 >>> (64 - 15))
    a22 = (a22 <<< 61 &&& @invalidate) ||| (a22 >>> (64 - 61))
    a03 = (a03 <<< 28 &&& @invalidate) ||| (a03 >>> (64 - 28))
    a08 = (a08 <<< 55 &&& @invalidate) ||| (a08 >>> (64 - 55))
    a13 = (a13 <<< 25 &&& @invalidate) ||| (a13 >>> (64 - 25))
    a18 = (a18 <<< 21 &&& @invalidate) ||| (a18 >>> (64 - 21))
    a23 = (a23 <<< 56 &&& @invalidate) ||| (a23 >>> (64 - 56))
    a04 = (a04 <<< 27 &&& @invalidate) ||| (a04 >>> (64 - 27))
    a09 = (a09 <<< 20 &&& @invalidate) ||| (a09 >>> (64 - 20))
    a14 = (a14 <<< 39 &&& @invalidate) ||| (a14 >>> (64 - 39))
    a19 = (a19 <<<  8 &&& @invalidate) ||| (a19 >>> (64 -  8))
    a24 = (a24 <<< 14 &&& @invalidate) ||| (a24 >>> (64 - 14))
    bnn = ~~~a12 &&& @invalidate
    kt = a06 ||| a12
    c0 = bxor(a00, kt)
    kt = bnn ||| a18
    c1 = bxor(a06, kt)
    kt = a18 &&& a24
    c2 = bxor(a12, kt)
    kt = a24 ||| a00
    c3 = bxor(a18, kt)
    kt = a00 &&& a06
    c4 = bxor(a24, kt)
    a00 = c0
    a06 = c1
    a12 = c2
    a18 = c3
    a24 = c4
    bnn = ~~~a22 &&& @invalidate
    kt = a09 ||| a10
    c0 = bxor(a03, kt)
    kt = a10 &&& a16
    c1 = bxor(a09, kt)
    kt = a16 ||| bnn
    c2 = bxor(a10, kt)
    kt = a22 ||| a03
    c3 = bxor(a16, kt)
    kt = a03 &&& a09
    c4 = bxor(a22, kt)
    a03 = c0
    a09 = c1
    a10 = c2
    a16 = c3
    a22 = c4
    bnn = ~~~a19 &&& @invalidate
    kt = a07 ||| a13
    c0 = bxor(a01, kt)
    kt = a13 &&& a19
    c1 = bxor(a07, kt)
    kt = bnn &&& a20
    c2 = bxor(a13, kt)
    kt = a20 ||| a01
    c3 = bxor(bnn, kt)
    kt = a01 &&& a07
    c4 = bxor(a20, kt)
    a01 = c0
    a07 = c1
    a13 = c2
    a19 = c3
    a20 = c4
    bnn = ~~~a17 &&& @invalidate
    kt = a05 &&& a11
    c0 = bxor(a04, kt)
    kt = a11 ||| a17
    c1 = bxor(a05, kt)
    kt = bnn ||| a23
    c2 = bxor(a11, kt)
    kt = a23 &&& a04
    c3 = bxor(bnn, kt)
    kt = a04 ||| a05
    c4 = bxor(a23, kt)
    a04 = c0
    a05 = c1
    a11 = c2
    a17 = c3
    a23 = c4
    bnn = ~~~a08 &&& @invalidate
    kt = bnn &&& a14
    c0 = bxor(a02, kt)
    kt = a14 ||| a15
    c1 = bxor(bnn, kt)
    kt = a15 &&& a21
    c2 = bxor(a14, kt)
    kt = a21 ||| a02
    c3 = bxor(a15, kt)
    kt = a02 &&& a08
    c4 = bxor(a21, kt)
    a02 = c0
    a08 = c1
    a14 = c2
    a15 = c3
    a21 = c4
    a00 = bxor(a00, Enum.at(@constants, index + 0))

    tt0 = bxor(a06, a09)
    tt1 = bxor(a07, a05)
    tt0 = bxor(tt0, a08) |> bxor(tt1)
    tt0 = (tt0 <<< 1 &&& @invalidate) ||| (tt0 >>> 63)
    tt2 = bxor(a24, a22)
    tt3 = bxor(a20, a23)
    tt0 = bxor(tt0, a21)
    tt2 = bxor(tt2, tt3)
    t0 =  bxor(tt0, tt2)

    tt0 = bxor(a12, a10)
    tt1 = bxor(a13, a11)
    tt0 = bxor(tt0, a14) |> bxor(tt1)
    tt0 = (tt0 <<< 1 &&& @invalidate) ||| (tt0 >>> 63)
    tt2 = bxor(a00, a03)
    tt3 = bxor(a01, a04)
    tt0 = bxor(tt0, a02)
    tt2 = bxor(tt2, tt3)
    t1 =  bxor(tt0, tt2)

    tt0 = bxor(a18, a16)
    tt1 = bxor(a19, a17)
    tt0 = bxor(tt0, a15) |> bxor(tt1)
    tt0 = (tt0 <<< 1 &&& @invalidate) ||| (tt0 >>> 63)
    tt2 = bxor(a06, a09)
    tt3 = bxor(a07, a05)
    tt0 = bxor(tt0, a08)
    tt2 = bxor(tt2, tt3)
    t2 =  bxor(tt0, tt2)

    tt0 = bxor(a24, a22)
    tt1 = bxor(a20, a23)
    tt0 = bxor(tt0, a21) |> bxor(tt1)
    tt0 = (tt0 <<< 1 &&& @invalidate) ||| (tt0 >>> 63)
    tt2 = bxor(a12, a10)
    tt3 = bxor(a13, a11)
    tt0 = bxor(tt0, a14)
    tt2 = bxor(tt2, tt3)
    t3 =  bxor(tt0, tt2)

    tt0 = bxor(a00, a03)
    tt1 = bxor(a01, a04)
    tt0 = bxor(tt0, a02) |> bxor(tt1)
    tt0 = (tt0 <<< 1 &&& @invalidate) ||| (tt0 >>> 63)
    tt2 = bxor(a18, a16)
    tt3 = bxor(a19, a17)
    tt0 = bxor(tt0, a15)
    tt2 = bxor(tt2, tt3)
    t4 =  bxor(tt0, tt2)

    a00 = bxor(a00, t0)
    a03 = bxor(a03, t0)
    a01 = bxor(a01, t0)
    a04 = bxor(a04, t0)
    a02 = bxor(a02, t0)
    a06 = bxor(a06, t1)
    a09 = bxor(a09, t1)
    a07 = bxor(a07, t1)
    a05 = bxor(a05, t1)
    a08 = bxor(a08, t1)
    a12 = bxor(a12, t2)
    a10 = bxor(a10, t2)
    a13 = bxor(a13, t2)
    a11 = bxor(a11, t2)
    a14 = bxor(a14, t2)
    a18 = bxor(a18, t3)
    a16 = bxor(a16, t3)
    a19 = bxor(a19, t3)
    a17 = bxor(a17, t3)
    a15 = bxor(a15, t3)
    a24 = bxor(a24, t4)
    a22 = bxor(a22, t4)
    a20 = bxor(a20, t4)
    a23 = bxor(a23, t4)
    a21 = bxor(a21, t4)
    a03 = (a03 <<< 36 &&& @invalidate) ||| (a03 >>> (64 - 36))
    a01 = (a01 <<<  3 &&& @invalidate) ||| (a01 >>> (64 -  3))
    a04 = (a04 <<< 41 &&& @invalidate) ||| (a04 >>> (64 - 41))
    a02 = (a02 <<< 18 &&& @invalidate) ||| (a02 >>> (64 - 18))
    a06 = (a06 <<<  1 &&& @invalidate) ||| (a06 >>> (64 -  1))
    a09 = (a09 <<< 44 &&& @invalidate) ||| (a09 >>> (64 - 44))
    a07 = (a07 <<< 10 &&& @invalidate) ||| (a07 >>> (64 - 10))
    a05 = (a05 <<< 45 &&& @invalidate) ||| (a05 >>> (64 - 45))
    a08 = (a08 <<<  2 &&& @invalidate) ||| (a08 >>> (64 -  2))
    a12 = (a12 <<< 62 &&& @invalidate) ||| (a12 >>> (64 - 62))
    a10 = (a10 <<<  6 &&& @invalidate) ||| (a10 >>> (64 -  6))
    a13 = (a13 <<< 43 &&& @invalidate) ||| (a13 >>> (64 - 43))
    a11 = (a11 <<< 15 &&& @invalidate) ||| (a11 >>> (64 - 15))
    a14 = (a14 <<< 61 &&& @invalidate) ||| (a14 >>> (64 - 61))
    a18 = (a18 <<< 28 &&& @invalidate) ||| (a18 >>> (64 - 28))
    a16 = (a16 <<< 55 &&& @invalidate) ||| (a16 >>> (64 - 55))
    a19 = (a19 <<< 25 &&& @invalidate) ||| (a19 >>> (64 - 25))
    a17 = (a17 <<< 21 &&& @invalidate) ||| (a17 >>> (64 - 21))
    a15 = (a15 <<< 56 &&& @invalidate) ||| (a15 >>> (64 - 56))
    a24 = (a24 <<< 27 &&& @invalidate) ||| (a24 >>> (64 - 27))
    a22 = (a22 <<< 20 &&& @invalidate) ||| (a22 >>> (64 - 20))
    a20 = (a20 <<< 39 &&& @invalidate) ||| (a20 >>> (64 - 39))
    a23 = (a23 <<<  8 &&& @invalidate) ||| (a23 >>> (64 -  8))
    a21 = (a21 <<< 14 &&& @invalidate) ||| (a21 >>> (64 - 14))
    bnn = ~~~a13 &&& @invalidate
    kt = a09 ||| a13
    c0 = bxor(a00, kt)
    kt = bnn ||| a17
    c1 = bxor(a09, kt)
    kt = a17 &&& a21
    c2 = bxor(a13, kt)
    kt = a21 ||| a00
    c3 = bxor(a17, kt)
    kt = a00 &&& a09
    c4 = bxor(a21, kt)
    a00 = c0
    a09 = c1
    a13 = c2
    a17 = c3
    a21 = c4
    bnn = ~~~a14 &&& @invalidate
    kt = a22 ||| a01
    c0 = bxor(a18, kt)
    kt = a01 &&& a05
    c1 = bxor(a22, kt)
    kt = a05 ||| bnn
    c2 = bxor(a01, kt)
    kt = a14 ||| a18
    c3 = bxor(a05, kt)
    kt = a18 &&& a22
    c4 = bxor(a14, kt)
    a18 = c0
    a22 = c1
    a01 = c2
    a05 = c3
    a14 = c4
    bnn = ~~~a23 &&& @invalidate
    kt = a10 ||| a19
    c0 = bxor(a06, kt)
    kt = a19 &&& a23
    c1 = bxor(a10, kt)
    kt = bnn &&& a02
    c2 = bxor(a19, kt)
    kt = a02 ||| a06
    c3 = bxor(bnn, kt)
    kt = a06 &&& a10
    c4 = bxor(a02, kt)
    a06 = c0
    a10 = c1
    a19 = c2
    a23 = c3
    a02 = c4
    bnn = ~~~a11 &&& @invalidate
    kt = a03 &&& a07
    c0 = bxor(a24, kt)
    kt = a07 ||| a11
    c1 = bxor(a03, kt)
    kt = bnn ||| a15
    c2 = bxor(a07, kt)
    kt = a15 &&& a24
    c3 = bxor(bnn, kt)
    kt = a24 ||| a03
    c4 = bxor(a15, kt)
    a24 = c0
    a03 = c1
    a07 = c2
    a11 = c3
    a15 = c4
    bnn = ~~~a16 &&& @invalidate
    kt = bnn &&& a20
    c0 = bxor(a12, kt)
    kt = a20 ||| a04
    c1 = bxor(bnn, kt)
    kt = a04 &&& a08
    c2 = bxor(a20, kt)
    kt = a08 ||| a12
    c3 = bxor(a04, kt)
    kt = a12 &&& a16
    c4 = bxor(a08, kt)
    a12 = c0
    a16 = c1
    a20 = c2
    a04 = c3
    a08 = c4
    a00 = bxor(a00, Enum.at(@constants, index + 1))
    t = a05
    a05 = a18
    a18 = a11
    a11 = a10
    a10 = a06
    a06 = a22
    a22 = a20
    a20 = a12
    a12 = a19
    a19 = a15
    a15 = a24
    a24 = a08
    a08 = t
    t = a01
    a01 = a09
    a09 = a14
    a14 = a02
    a02 = a13
    a13 = a23
    a23 = a04
    a04 = a21
    a21 = a16
    a16 = a03
    a03 = a17
    a17 = a07
    a07 = t

    edit = [a00, a01, a02, a03, a04, a05, a06, a07, a08, a09, a10, a11, a12,
      a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24]

    %{value | state: edit}
    |> process_block_loop(index + 2)
  end

  defp process_block_loop(value, _index), do: value

  defp process_block_decode_loop(%__MODULE__{} = value, index) when index < value.block_length do
    decode_index = index >>> 3
    current = Enum.at(value.state, decode_index)
    {value2, tail} = value.input_cut |> decode_long()
    long = bxor(current, value2)
    update_list = List.replace_at(value.state, decode_index, long)

    %{value | state: update_list, input_cut: tail}
    |> process_block_decode_loop(index + 8)
  end

  defp process_block_decode_loop(%__MODULE__{} = data, _index), do: data

  defp decode_long(data) do
    <<h::8, g::8, f::8, e::8, d::8, c::8, b::8, a::8, tail::binary>> = data

    long = h &&& 0xFF
    ||| (g &&& 0xFF) <<< 8
    ||| (f &&& 0xFF) <<< 16
    ||| (e &&& 0xFF) <<< 24
    ||| (d &&& 0xFF) <<< 32
    ||| (c &&& 0xFF) <<< 40
    ||| (b &&& 0xFF) <<< 48
    ||| (a &&& 0xFF) <<< 56

    {long, tail}
  end
end
