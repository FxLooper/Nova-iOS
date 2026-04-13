import SwiftUI
import WebKit

struct OrbWebView: UIViewRepresentable {
    let state: String
    let audioLevel: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.loadHTMLString(orbHTML, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let safeState = state.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("setOrbState('\(safeState)', \(audioLevel))") { _, _ in }
    }

    private var orbHTML: String {
        """
        <!DOCTYPE html>
        <html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
        <style>
        * { margin: 0; padding: 0; }
        body { background: transparent; overflow: hidden; }
        canvas { display: block; }
        </style>
        </head><body>
        <canvas id="c"></canvas>
        <!-- TODO: Bundle three.min.js locally for offline support (add to Xcode project Resources) -->
        <script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
        <script>
        const canvas = document.getElementById('c');
        const W = window.innerWidth, H = window.innerHeight;
        canvas.width = W; canvas.height = H;

        const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
        renderer.setSize(W, H);
        renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
        renderer.setClearColor(0x000000, 0);

        const scene = new THREE.Scene();
        const camera = new THREE.PerspectiveCamera(52, W / H, 0.1, 2000);
        camera.position.z = 320;

        // Lights
        const oLight = new THREE.PointLight(0x8b7355, 6, 600);
        const bLight = new THREE.PointLight(0x4a6680, 5, 600);
        scene.add(new THREE.AmbientLight(0x2a2a3a, 3), oLight, bLight);

        // Core particles
        const pVert = `attribute float aSize; attribute vec3 aColor; attribute float aPhase; attribute float aSpeed;
        uniform float uTime; uniform float uEnergy; uniform vec3 uAccent;
        varying vec3 vColor; varying float vAlpha;
        void main(){
            vColor = mix(aColor, uAccent, uEnergy * 0.5);
            float p = 1.0 + sin(uTime * aSpeed + aPhase) * 0.065 + uEnergy * 0.08;
            vec4 mv = modelViewMatrix * vec4(position * p, 1.0);
            gl_PointSize = aSize * (280.0 / -mv.z) * (1.0 + uEnergy * 0.3);
            gl_Position = projectionMatrix * mv;
            vAlpha = 0.35 + sin(uTime * aSpeed * 0.55 + aPhase + 1.0) * 0.35;
        }`;
        const pFrag = `varying vec3 vColor; varying float vAlpha;
        void main(){
            vec2 uv = gl_PointCoord - 0.5; float d = length(uv);
            if(d > 0.5) discard;
            gl_FragColor = vec4(vColor, vAlpha * (1.0 - smoothstep(0.05, 0.5, d)) * 0.7);
        }`;

        const N = 6000;
        const geo = new THREE.BufferGeometry();
        const pos = new Float32Array(N*3), aCol = new Float32Array(N*3), aSz = new Float32Array(N), aPh = new Float32Array(N), aSp = new Float32Array(N);
        for(let i = 0; i < N; i++){
            const phi = Math.acos(2*Math.random()-1), theta = Math.random()*Math.PI*2, r = 46+Math.random()*62;
            aPh[i] = Math.random()*Math.PI*2; aSp[i] = 0.7+Math.random()*2.2;
            pos[i*3] = Math.sin(phi)*Math.cos(theta)*r;
            pos[i*3+1] = Math.sin(phi)*Math.sin(theta)*r;
            pos[i*3+2] = Math.cos(phi)*r;
            const darkness = 0.5+Math.random()*0.5, variant = Math.random();
            if(variant<0.5){aCol[i*3]=0.10*darkness;aCol[i*3+1]=0.10*darkness;aCol[i*3+2]=0.18*darkness;}
            else if(variant<0.8){aCol[i*3]=0.18*darkness;aCol[i*3+1]=0.18*darkness;aCol[i*3+2]=0.27*darkness;}
            else{aCol[i*3]=0.35*darkness;aCol[i*3+1]=0.35*darkness;aCol[i*3+2]=0.42*darkness;}
            aSz[i] = 0.5+Math.random()*2.2;
        }
        geo.setAttribute('position', new THREE.BufferAttribute(pos,3));
        geo.setAttribute('aColor', new THREE.BufferAttribute(aCol,3));
        geo.setAttribute('aSize', new THREE.BufferAttribute(aSz,1));
        geo.setAttribute('aPhase', new THREE.BufferAttribute(aPh,1));
        geo.setAttribute('aSpeed', new THREE.BufferAttribute(aSp,1));

        const orbMat = new THREE.ShaderMaterial({
            uniforms: { uTime:{value:0}, uEnergy:{value:0}, uAccent:{value:new THREE.Vector3(0.42,0.49,0.55)} },
            vertexShader: pVert, fragmentShader: pFrag,
            transparent: true, depthWrite: false, blending: THREE.NormalBlending
        });
        const orbPoints = new THREE.Points(geo, orbMat);
        scene.add(orbPoints);

        // Rings
        const allRingMats = [];
        function galaxyRing(radius, count, thickness, spread, color1, color2, rx, ry, rz){
            const group = new THREE.Group();
            const positions = new Float32Array(count*3), colors = new Float32Array(count*3), sizes = new Float32Array(count);
            for(let i=0;i<count;i++){
                const angle=Math.random()*Math.PI*2, r=radius+(Math.random()-0.5)*thickness, z=(Math.random()-0.5)*spread;
                positions[i*3]=Math.cos(angle)*r; positions[i*3+1]=Math.sin(angle)*r; positions[i*3+2]=z;
                const c=new THREE.Color(color1).lerp(new THREE.Color(color2),Math.random());
                colors[i*3]=c.r; colors[i*3+1]=c.g; colors[i*3+2]=c.b; sizes[i]=0.5+Math.random()*2.5;
            }
            const g=new THREE.BufferGeometry();
            g.setAttribute('position',new THREE.BufferAttribute(positions,3));
            g.setAttribute('color',new THREE.BufferAttribute(colors,3));
            g.setAttribute('size',new THREE.BufferAttribute(sizes,1));
            const mat=new THREE.ShaderMaterial({
                uniforms:{uTime:{value:0},uEnergy:{value:0},uPhase:{value:Math.random()*Math.PI*2}},
                vertexShader:`attribute float size;uniform float uTime;uniform float uEnergy;uniform float uPhase;varying vec3 vColor;varying float vA;void main(){vColor=color;float pulse=(0.7+0.3*sin(uTime*1.5+position.x*0.1+uPhase))*(1.0+uEnergy*0.5);vA=pulse;vec4 mv=modelViewMatrix*vec4(position,1.0);gl_PointSize=size*(250.0/-mv.z)*pulse;gl_Position=projectionMatrix*mv;}`,
                fragmentShader:`varying vec3 vColor;varying float vA;void main(){vec2 uv=gl_PointCoord-0.5;float d=length(uv);if(d>0.5)discard;gl_FragColor=vec4(vColor,vA*(1.0-smoothstep(0.1,0.5,d))*0.85);}`,
                transparent:true,depthWrite:false,blending:THREE.NormalBlending,vertexColors:true
            });
            allRingMats.push(mat);
            group.add(new THREE.Points(g,mat));
            group.rotation.set(rx,ry,rz);
            return group;
        }

        const ringGroups = [
            {g:galaxyRing(90,2800,16,12,0x0e0e1a,0x1a1a2e,Math.PI/2+0.08,0.04,0), sx:0.0005,sy:0.005,sz:0.003},
            {g:galaxyRing(101,1800,12,8,0x08080f,0x151520,0.38,0.85,0.1), sx:0.0012,sy:0.004,sz:-0.003},
            {g:galaxyRing(75,1800,12,8,0x101020,0x0a0a14,0.75,1.15,0.35), sx:0.0015,sy:-0.005,sz:-0.002},
        ];
        ringGroups.forEach(({g}) => scene.add(g));

        // Core sprites
        function makeSprite(size, stops, op){
            const cv=document.createElement('canvas');cv.width=512;cv.height=512;
            const g=cv.getContext('2d'),gr=g.createRadialGradient(256,256,0,256,256,256);
            stops.forEach(([s,c])=>gr.addColorStop(s,c));
            g.fillStyle=gr;g.fillRect(0,0,512,512);
            const sp=new THREE.Sprite(new THREE.SpriteMaterial({map:new THREE.CanvasTexture(cv),transparent:true,blending:THREE.NormalBlending,opacity:op,depthWrite:false}));
            sp.scale.set(size,size,1);return sp;
        }
        const coreSprite=makeSprite(140,[[0,'rgba(26,26,46,0.5)'],[0.2,'rgba(26,26,46,0.25)'],[0.5,'rgba(26,26,46,0.08)'],[0.8,'rgba(26,26,46,0.02)'],[1,'rgba(26,26,46,0)']],0.7);
        const midSprite=makeSprite(280,[[0,'rgba(26,26,46,0.2)'],[0.3,'rgba(26,26,46,0.08)'],[0.7,'rgba(26,26,46,0.02)'],[1,'rgba(26,26,46,0)']],0.5);
        scene.add(midSprite, coreSprite);

        // State
        const ACCENTS = {
            idle: new THREE.Vector3(0.42,0.49,0.55),
            listening: new THREE.Vector3(0.55,0.37,0.24),
            thinking: new THREE.Vector3(0.35,0.43,0.35),
            speaking: new THREE.Vector3(0.24,0.35,0.43),
        };
        let currentState = 'idle', energy = 0, targetEnergy = 0;

        window.setOrbState = function(state, audioLevel) {
            currentState = state || 'idle';
            if(state === 'listening') targetEnergy = audioLevel || 0.3;
            else if(state === 'thinking') targetEnergy = 0.5;
            else if(state === 'speaking') targetEnergy = audioLevel || 0.4;
            else targetEnergy = 0;
        };

        // Animate
        let frame = 0;
        function animate(){
            requestAnimationFrame(animate);
            frame++;
            const t = frame * 0.016;
            energy += (targetEnergy - energy) * 0.08;
            const accent = ACCENTS[currentState] || ACCENTS.idle;
            const pulse = 1 + Math.sin(t*1.85)*0.052 + energy*0.08;
            const breathe = 1 + Math.sin(t*0.42)*0.022;
            const thinkBoost = currentState === 'thinking' ? 0.012 : 0;

            orbMat.uniforms.uTime.value = t;
            orbMat.uniforms.uEnergy.value = energy;
            orbMat.uniforms.uAccent.value = accent;
            orbPoints.rotation.y += 0.0025 + energy*0.003 + thinkBoost;
            orbPoints.rotation.x += 0.0008 + thinkBoost*0.3;
            orbPoints.scale.setScalar(pulse * breathe);

            allRingMats.forEach(m => { m.uniforms.uTime.value=t; m.uniforms.uEnergy.value=energy; });
            const speedMult = 1 + energy*2.5;
            ringGroups.forEach(({g,sx,sy,sz}) => { g.rotation.x+=sx*speedMult; g.rotation.y+=sy*speedMult; g.rotation.z+=sz*speedMult; });

            oLight.position.set(Math.sin(t*0.7)*100, Math.cos(t*0.5)*80, Math.sin(t*0.3)*90);
            coreSprite.material.opacity = 0.55 + energy*0.15;
            midSprite.material.opacity = 0.35 + energy*0.12;

            renderer.render(scene, camera);
        }
        animate();
        </script>
        </body></html>
        """
    }
}
