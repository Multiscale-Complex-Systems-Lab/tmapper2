function tcm_n = normtcm(tcm,varargin)
%NORMTCM normalize temporal connectivity matrix by its maximal value that
%is not Inf.
%   tcm_n = normtcm(tcm)
% parameters:
%   normtype: how to compute the normalizing factor. 'max' (default): the
%   matrix's maximum finite value. 'norm': the matrix norm (norm(tcm(:))).
%   infreplace: how to handle Inf entries before normalizing. 'max'
%   (default): replace with the matrix's maximum finite value. 'nan':
%   replace with NaN.
%{
~ Author: Mengsen Zhang <mengsenzhang@gmail.com> 2019 ~
modifications:
(10-13-2020) add more options for normalization
(7-19-2026) document the 'normtype'/'infreplace' parameters (existed
since 10-13-2020 but were never listed in the header).
%}
p = inputParser;
p.addParameter('normtype','max'); % normalize by max (default) or norm
p.addParameter('infreplace','max'); 
p.parse(varargin{:});
par = p.Results;

% -- handle inf
switch par.infreplace
    case 'max'
        % nothing finite means no stand-in for Inf; the bare assignment
        % fails with a shape error that names nothing useful.
        finiteTcm = tcm(tcm<Inf);
        if any(isinf(tcm(:))) && isempty(finiteTcm)
            error('normtcm:allInfinite', ...
                'tcm has no finite entries, so there is no maximum to replace Inf with.');
        end
        tcm(tcm==Inf) = max(finiteTcm);
    case 'nan'
        tcm(tcm==Inf) = nan;
    otherwise
        % previously fell through silently, leaving Inf in place to be
        % divided away into NaN/0 further down
        error('normtcm:invalidInfReplace', ...
            'infreplace must be ''max'' or ''nan''; got ''%s''.', char(string(par.infreplace)));
end

% -- normalize
switch par.normtype
    case 'max'
        normfactor = max(tcm(:));
    case 'norm'
        normfactor = norm(tcm(:));
    otherwise
        % previously left normfactor undefined, surfacing as
        % MATLAB:UndefinedFunction rather than naming the real problem
        error('normtcm:invalidNormType', ...
            'normtype must be ''max'' or ''norm''; got ''%s''.', char(string(par.normtype)));
end

if normfactor~=0
    tcm_n = tcm/normfactor;
else
    tcm_n = tcm;
end
end

