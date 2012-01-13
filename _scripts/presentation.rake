
require 'pathname'     #pathname icermesini saglar.
require 'pythonconfig' #pythonconfig icermesini  saglar.
require 'yaml'         #icermesini saglar.

CONFIG = Config.fetch('presentation', {})              #presentation dosyasini getirir.

PRESENTATION_DIR = CONFIG.fetch('directory', 'p')      #directory dosyasina p'yi aktar.
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg') #confile dosyasina_templates/presentation.cfg dosyayi getirir.
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html')                     #PRESENTATION_DR ile index.html'yi birlestir  ve index_file'ye aktar.
IMAGE_GEOMETRY = [ 733, 550 ]      #Resim geometrilerini sabitlestirir.
DEPEND_KEYS    = %w(source css js) #css'yi ve js'yi bagimli anahtar olarak al.
DEPEND_ALWAYS  = %w(media)         
TASKS = {
    :index   => 'sunumları indeksle',  # gorev listesi ve yorumlar.
    :build   => 'sunumları oluştur',   # ....
    :clean   => 'sunumları temizle',   # ....
    :view    => 'sunumları görüntüle', # ....
    :run     => 'sunumları sun',       # ....
    :optim   => 'resimleri iyileştir', # ....
    :default => 'öntanımlı görev',     # ....
}

presentation   = {} 
tag            = {} 

class File #File sinifi acar
  @@absolute_path_here = Pathname.new(Pathname.pwd)
  def self.to_herepath(path)
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end
                              
  def self.to_filelist(path)                                        #dosya  yolunu konturol eder ayniysa listeler.
    File.directory?(path) ?                                         #...
      FileList[File.join(path, '*')].select { |f| File.file?(f) } : #...
      [path]
  end
end
                                       
def png_comment(file, string) #olusturan dosya yolunu stringi yorumlar.     
  require 'chunky_png'        #...
  require 'oily_png'          #...

  image = ChunkyPNG::Image.from_file(file) #acilan dosyaya raked yorumu yapar kaydeder.
  image.metadata['Comment'] = 'raked'      #...
  image.save(file)                         #...
end

def png_optim(file, threshold=40000) #her bir slayt boyunun optimizasyonunu saglar.
  return if File.new(file).size < threshold
  sh "pngnq -f -e .png-nq #{file}"
  out = "#{file}-nq"
  if File.exist?(out)                                       #dosya varmi yokmu
    $?.success? ? File.rename(out, file) : File.delete(out) #dosya varsa adini  file olarak degisitir ve out dosyasini sil
  end
  png_comment(file, 'raked')                                #raked
end

def jpg_optim(file)                     #jpg dosyalarini optimizasyonu  saglar
  sh "jpegoptim -q -m80 #{file}"        #bos
  sh "mogrify -comment 'raked' #{file}" #raked
end

def optim
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"] #jpg ve png dosyalarini listeler

  [pngs, jpgs].each do |a|                                             #tum jpeg ve png dosyalari sabitlenmis hala gelir 
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ } 
  end

  (pngs + jpgs).each do |f|
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i } #tum jpeg ve png dosyalarinin boyutunu belirler
    size, i = [w, h].each_with_index.max              							#....
    if size > IMAGE_GEOMETRY[i]												    #....
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s							#....
      sh "mogrify -resize #{arg} #{f}"  										#....
    end
  end

  pngs.each { |f| png_optim(f) }  #tum jpg ve png dosyalari belirlenen boyutlari uygun hale getirilir
  jpgs.each { |f| jpg_optim(f) }  #...
  (pngs + jpgs).each do |f|       #...
    name = File.basename f        #...
    FileList["*/*.md"].each do |src| #...
      sh "grep -q '(.*#{name})' #{src} && touch #{src}" #...
    end
  end
end

default_conffile = File.expand_path(DEFAULT_CONFFILE)

FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir|
  next unless File.directory?(dir) #slayt dosyalarinin uzantilarini belirler
  chdir dir do
    name = File.basename(dir)
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    config = File.open(conffile, "r") do |f|
      PythonConfig::ConfigParser.new(f)
    end

    landslide = config['landslide']
    if ! landslide #landslide kismi tanimlanmis mi  diye konturol eder
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış" #tanimlanmamissa hata ciktisi verir
      exit 1
    end

    if landslide['destination'] #destination ayarini kulanilip kulanilmadigini konturol eder
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin" #kulanilmissa hata verir
      exit 1
    end

    if File.exists?('index.md')            #index.md'nin olup olmadigini konturol eder
      base = 'index'                       #...
      ispublic = true                      #disari aciktir
    elsif File.exists?('presentation.md')  #presentation.md'nin olup olmadigini konturol eder
      base = 'presentation'
      ispublic = false                     #disari kapali
	else # bunlarin disindaki durumlarda ise 
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı"
      exit 1
    end

    basename = base + '.html'                     #.md dosyasini .html yap
    thumbnail = File.to_herepath(base + '.png')   #png uzantisiyla baslangic yolunu olustur
    target = File.to_herepath(basename)           #heef olustur

    deps = []
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
    end

    deps.map! { |e| File.to_herepath(e) }
    deps.delete(target)    #target sil
    deps.delete(thumbnail) #thumbnail sil

    tags = []

   presentation[dir] = {
      :basename  => basename,	# üreteceğimiz sunum dosyasının baz adı
      :conffile  => conffile,	# landslide konfigürasyonu (mutlak dosya yolu)
      :deps      => deps,	# sunum bağımlılıkları
      :directory => dir,	# sunum dizini (tepe dizine göreli)
      :name      => name,	# sunum ismi
      :public    => ispublic,	# sunum dışarı açık mı
      :tags      => tags,	# sunum etiketleri
      :target    => target,	# üreteceğimiz sunum dosyası (tepe dizine göreli)
      :thumbnail => thumbnail, 	# sunum için küçük resim
    }
  end
end

presentation.each do |k, v| #sunum dosyalarindaki eksik taglari tamamlar
  v[:tags].each do |t|
    tag[t] ||= []
    tag[t] << k
  end
end

tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten] #gorev haritasi

presentation.each do |presentation, data|
  ns = namespace presentation do             #isim  uzayi olustur 
    file data[:target] => data[:deps] do |t| #target icerigini aktar, sunumu olustur
      chdir presentation do
        sh "landslide -i #{data[:conffile]}"
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
        unless data[:basename] == 'presentation.html'
          mv 'presentation.html', data[:basename]
        end
      end
    end

    file data[:thumbnail] => data[:target] do #resmi hedefe gonder
      next unless data[:public]               #bir sonrakinin public olup olmadigni kontrol et
      sh "cutycapt " +
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " + #kucuk resimlerin boyutunu duzenle en uygun  hala getir 
          "--min-width=1024 " +
          "--min-height=768 " +
          "--delay=1000"
      sh "mogrify -resize 240 #{data[:thumbnail]}"
      png_optim(data[:thumbnail])
    end

    task :optim do #uygun hala getirme islemi yapiliyor 
      chdir presentation do
        optim
      end
    end

    task :index => data[:thumbnail]                #gorevler arasindaki index resime uygular

    task :build => [:optim, data[:target], :index] #gorevler arasindaki build uygular

    task :view do
      if File.exists?(data[:target])               #target belirtilen dosyanin olup olmadigini konturol et
        sh "touch #{data[:directory]}; #{browse_command data[:target]}" #eger dosya varsa islemi uygula
      else
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin"      #yoksa ekrana hata ciktisi ver 
      end
    end

    task :run => [:build, :view]

    task :clean do
      rm_f data[:target]
      rm_f data[:thumbnail]
    end

    task :default => :build #varsayilan gorev build
  end

  ns.tasks.map(&:to_s).each do |t|
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]
    tasktab[name][:tasks] << t
  end
end

namespace :p do  #isim uzayinda eklenen yeni gorevleri isim ve bilgiler olustur
  tasktab.each do |name, info|
    desc info[:desc]
    task name => info[:tasks]
    task name[0] => name
  end

  task :build do
    index = YAML.load_file(INDEX_FILE) || {} #INDEX_FILE yazdir
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort #dosyalari sec
    unless index and presentations == index['presentations'] #eger esit ise INDEX_FILE'i ac ve icerisine index.to_yaml'i ve   yazar
      index['presentations'] = presentations
      File.open(INDEX_FILE, 'w') do |f|
        f.write(index.to_yaml)
        f.write("---\n")
      end
    end
  end

  desc "sunum menüsü"
  task :menu do                         #menu gorev islemlerin isimini, rengini, olusturulmasini duzenler
    lookup = Hash[                      #...
      *presentation.sort_by do |k, v|   #...
        File.mtime(v[:directory])       #...
      end
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
    name = choose do |menu|
      menu.default = "1"    #on tanimli deger 1'dir
      menu.prompt = color(
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke #rake'yi calistirir
  end
  task :m => :menu   #olusturulan m gorevi, menu menu gorev araciligiya calistirilir
end

desc "sunum menüsü"
task :p => ["p:menu"]     # #menuyu p calistirir
task :presentation => :p  #presentation gorevini olusturur