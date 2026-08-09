function M = zerodiag(M)
%ZERODIAG set diagonal to zero
if size(M,1)~=size(M,2), error('This function only takes square matrices.');end
M(1:size(M,1)+1:end)=0;% linear indexing -- logical(eye(n)) allocated a full
                       % n-by-n double plus a logical copy to address n entries
end

