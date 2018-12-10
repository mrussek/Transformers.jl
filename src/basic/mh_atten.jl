using Flux
using Flux: @treelike
using Flux.Tracker
using LinearAlgebra: LowerTriangular

struct MultiheadAttention
    head::Int
    future::Bool
    iproj::Dense
    oproj::Dense
end

@treelike MultiheadAttention

MultiheadAttention(head::Int,
                   is::Int,
                   hs::Int,
                   os::Int; future::Bool=true) = (hs%head !=0 && error("hidden size can not be divide by head");
                                                 MultiheadAttention(head,
                                                                    future,
                                                                    Dense(3is, 3hs*head),
                                                                    Dense(hs*head, os)))

function (mh::MultiheadAttention)(query::AbstractArray{T, 3},
                                  key::AbstractArray{T, 3},
                                  value::AbstractArray{T, 3};
                                  mask=nothing) where T

    bnum = size(query)[end]
    bqs = [query[:, :, b] for b = 1:bnum]
    bks = [key[:, :, b] for b = 1:bnum]
    bvs = [value[:, :, b] for b = 1:bnum]

    if mask !== nothing
        bms = [value[:, :, b] for b = 1:bnum]
        atten = cat(map((q,k,v, m)->mh(q, k, v; mask=m), bqs, bks, bvs, bms)...; dims=3)
    else
        atten = cat(map((q,k,v)->mh(q, k, v; mask=nothing), bqs, bks, bvs)...; dims=3)
    end
    atten
end


function (mh::MultiheadAttention)(query::AbstractArray{T, 2},
                                  key::AbstractArray{T, 2},
                                  value::AbstractArray{T, 2};
                                  mask=nothing) where T
    # size(query) == (dims, seq_len)
    # dim = size(query)[1]

    ip = cat(query, key, value; dims=1)
    ipj = mh.iproj(ip)

    h = div(size(ipj)[1], 3) #h == hs * head
    hs = div(h, mh.head)

    # selectdim/view break on gpu
    # ipq = selectdim(ipj, 1, 1:h) # size(ipq) == (h, seq_len)
    # ipk = selectdim(ipj, 1, h+1:2h)
    # ipv = selectdim(ipj, 1, 2h+1:3h)

    # hq = [Tracker.collect(selectdim(ipq, 1, (i-1)*hs+1:i*hs)) for i = 1:mh.head] # head * size(hq[1]) == head * (hs, seq_len)
    # hk = [Tracker.collect(selectdim(ipk, 1, (i-1)*hs+1:i*hs)) for i = 1:mh.head]
    # hv = [Tracker.collect(selectdim(ipv, 1, (i-1)*hs+1:i*hs)) for i = 1:mh.head]

    ipq = ipj[1:h, :] # size(ipq) == (h, seq_len)
    ipk = ipj[h+1:2h, :]
    ipv = ipj[2h+1:3h, :]

    hq = [ipq[(i-1)*hs+1:i*hs, :] for i = 1:mh.head] # head * size(hq[1]) == head * (hs, seq_len)
    hk = [ipk[(i-1)*hs+1:i*hs, :] for i = 1:mh.head]
    hv = [ipv[(i-1)*hs+1:i*hs, :] for i = 1:mh.head]


    # size(atten) == (head*hs, seq_len)
    atten = map((q,k,v)->attention(q, k, v; mask=mask, future=mh.future), hq, hk, hv)
    atten = cat(atten...; dims=1)

    mh.oproj(atten)
end

function attention(query::AbstractArray{T, 2},
                   key::AbstractArray{T, 2},
                   value::AbstractArray{T, 2};
                   mask=nothing, future::Bool = false) where T
    # size(query) == (dims, {q,k}_seq_len) == size(key) == size(value)
    # size(score) == (k_seq_len, q_seq_len)
    dk = size(key)[1]
    score = key' * query
    score = score ./ sqrt(dk)

    if mask !== nothing
        @. mask = (1 - mask) * -1e9
        score += mask
    end

    if !future
        fmask = fill(convert(T, 1), size(score))
        fmask .-= one(fmask)
        fmask .= -1e9 .* collect(LowerTriangular(fmask))
        fmask = device(fmask)
        score += fmask
    end

    score = softmax(score)
    value * score #size(return) == (dims, q_seq_len)
end

