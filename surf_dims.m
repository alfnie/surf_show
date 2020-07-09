function dim=surf_dims(resolution)
if numel(resolution)==1
    nvertices=2+10*2^(2*resolution-2);
    n=[1,1,factor(nvertices)];
    minx=inf;
    for n1=1:numel(n)-2,
        for n2=n1+1:numel(n)-1,
            for n3=n2+1:numel(n)
                x=[prod(n(1:n1)),prod(n(n2:n3-1)),prod(n(n3:end))];
                tminx=std(x);
                if tminx<minx, dim=x; tminx=minx; end
            end
        end
    end
else
    dim=resolution;
    nvertices=prod(dim);
    resolution=round((log((nvertices-2)/10)/log(2)+2)/2);
    nvertices2=2+10*2^(2*resolution-2);
    if nvertices~=nvertices2, if ~nargout, disp('not recognized data dimensions'); end; dim=[]; return; end
    for n1=1:12
        dim2=surf_dims(n1);
        if isequal(dim,dim2),
            dim=n1;
            return;
        end
    end
    dim=[];
end



