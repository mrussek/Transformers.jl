using Flux
using Flux: @treelike

using ..Basic
using ..Stacks

struct Bert
  pe::PositionEmbedding
  ts::Stack
  drop::Dropout
end

@treelike Bert

function Bert(size::Int, head::Int, ps::Int, layer::Int;
              max_len::Int = 512, trainable = true, act = gelu, pdrop = 0.1, att_pdrop = 0.1)
  rem(size,  head) != 0 && error("size not divisible by head")
  Bert(size, head, div(size, head), ps, layer; max_len=max_len, trainable=trainable, act=act, pdrop=pdrop, att_pdrop=att_pdrop)
end

function Bert(size::Int, head::Int, hs::Int, ps::Int, layer::Int; max_len::Int = 512, trainable = true, act = gelu, pdrop = 0.1, att_pdrop = 0.1)
  Bert(
    PositionEmbedding(size, max_len; trainable=trainable),
    Stack(
      @nntopo_str "x':x => $layer",
      [
        Transformer(size, head, hs, ps; future=true, act=act, pdrop=att_pdrop)
        for i = 1:layer
      ]
    ),
    Dropout(pdrop))
end


