function dat = toVec( dat)
%TOVEC convert any cell data to a single vector by all numeric content of
%the cells into a column vector.
%   dat = toVec( dat)
%{
created 2016/08/03, by MZ
%}


if iscell(dat)
    try
        dat=cell2mat(dat);
        dat=dat(:);
    catch
        dat=toVec(cellfun(@toVec,dat(:),'uniformoutput',false));
    end
end
if isnumeric(dat) || islogical(dat)
    dat=dat(:);
    return
end
end

